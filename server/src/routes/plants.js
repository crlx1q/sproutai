import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { upload, saveImage, toGeminiJpeg } from '../utils/upload.js';
import { analyzePlantImage } from '../services/gemini.js';
import { Plant } from '../models/Plant.js';
import { JournalEntry } from '../models/JournalEntry.js';
import { Reminder } from '../models/Reminder.js';

const router = Router();
router.use(requireAuth);

function plantView(plant) {
  const obj = plant.toObject({ virtuals: false });
  obj.wateringDueAt = plant.wateringDueAt();
  obj.needsWater = plant.wateringDueAt() <= new Date();
  obj.fertilizingDueAt = plant.fertilizingDueAt();
  obj.needsFertilizer = plant.fertilizingDueAt() <= new Date();
  obj.checkupDueAt = plant.checkupDueAt();
  obj.needsCheckup = plant.checkupDueAt() <= new Date();
  return obj;
}

router.get('/', async (req, res) => {
  const plants = await Plant.find({ userId: req.user._id }).sort({ createdAt: -1 });
  res.json({ plants: plants.map(plantView) });
});

// Задачи на сегодня: какие растения просят полив.
router.get('/tasks/today', async (req, res) => {
  const plants = await Plant.find({ userId: req.user._id });
  const now = new Date();
  const needWater = plants.filter((p) => p.wateringDueAt() <= now).map(plantView);
  res.json({ needWater, count: needWater.length });
});

router.post('/water-all', async (req, res) => {
  const plants = await Plant.find({ userId: req.user._id });
  const now = new Date();
  const due = plants.filter((p) => p.wateringDueAt() <= now);
  for (const p of due) {
    p.lastWateredAt = now;
    await p.save();
  }
  await Reminder.updateMany(
    { userId: req.user._id, plantId: { $in: due.map((p) => p._id) }, type: 'watering' },
    [{ $set: { nextDueAt: { $dateAdd: { startDate: '$$NOW', unit: 'day', amount: '$intervalDays' } } } }]
  );
  res.json({ watered: due.length });
});

function parseMaybe(value) {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch {
      return undefined;
    }
  }
  return value;
}

router.post('/', upload.single('photo'), async (req, res) => {
  const {
    name, species, location, care, healthScore, healthStatus, isHealthy, diagnosis, scanId,
    origin, stage, plantedAt, growthGoal,
  } = req.body || {};
  if (!name) return res.status(400).json({ error: 'Нужно имя растения' });

  let photoUrl = req.body.photoUrl || null;
  if (req.file) photoUrl = await saveImage(req.file.buffer);

  const careObj = parseMaybe(care);

  const validStages = ['seed', 'sprout', 'seedling', 'growing', 'mature', 'flowering'];
  const isGrown = origin === 'grown';
  const doc = {
    userId: req.user._id,
    name,
    species: species || '',
    location: location === 'outdoor' ? 'outdoor' : 'indoor',
    origin: isGrown ? 'grown' : 'existing',
    stage: validStages.includes(stage) ? stage : (isGrown ? 'seedling' : 'mature'),
    plantedAt: plantedAt ? new Date(plantedAt) : (isGrown ? new Date() : null),
    growthGoal: growthGoal || '',
    photoUrl,
    care: careObj,
    lastWateredAt: new Date(),
  };

  // Переносим результат скана, чтобы здоровье не сбрасывалось в дефолтные 90%.
  const score = healthScore !== undefined ? Number(healthScore) : undefined;
  const healthy = typeof isHealthy === 'string' ? isHealthy === 'true' : isHealthy;
  if (Number.isFinite(score)) {
    doc.healthScore = Math.max(0, Math.min(100, Math.round(score)));
  }
  if (['thriving', 'needs_attention', 'sick'].includes(healthStatus)) {
    doc.healthStatus = healthStatus;
  } else if (doc.healthScore !== undefined) {
    doc.healthStatus =
      healthy === false
        ? doc.healthScore >= 55
          ? 'needs_attention'
          : 'sick'
        : 'thriving';
  }
  const diag = parseMaybe(diagnosis);
  if (diag && (diag.title || diag.description)) {
    doc.lastDiagnosis = {
      isHealthy: healthy !== undefined ? healthy : diag.isHealthy ?? true,
      title: diag.title || '',
      description: diag.description || '',
      confidence: Number(diag.confidence) || 0,
      treatmentPlan: Array.isArray(diag.treatmentPlan) ? diag.treatmentPlan : [],
      scanId: scanId || undefined,
      scannedAt: new Date(),
    };
  }

  // Автозаполнение по фото: если результат скана не передан, но есть фото —
  // просим ИИ определить вид, здоровье и уход (кнопка «+», режим «с нуля»).
  if (req.file && !Number.isFinite(score)) {
    try {
      const geminiJpeg = await toGeminiJpeg(req.file.buffer);
      const result = await analyzePlantImage(geminiJpeg, {
        plantContext: {
          name: doc.name,
          species: doc.species,
          location: doc.location,
          stage: doc.stage,
          plantedAt: doc.plantedAt,
        },
        mode: isGrown ? 'grow' : 'diagnose',
      });
      if (result && result.isPlant) {
        doc.healthScore = result.healthScore;
        doc.healthStatus = result.isHealthy
          ? 'thriving'
          : result.healthScore >= 55 ? 'needs_attention' : 'sick';
        if (!doc.species && result.species) doc.species = result.species;
        const validGrowth = ['seed', 'sprout', 'seedling', 'growing', 'mature', 'flowering'];
        if (isGrown && validGrowth.includes(result.growthStage)) {
          doc.stage = result.growthStage;
        }
        if (result.diagnosis && (result.diagnosis.title || result.diagnosis.description)) {
          doc.lastDiagnosis = {
            isHealthy: result.isHealthy,
            title: result.diagnosis.title || '',
            description: result.diagnosis.description || '',
            confidence: Number(result.diagnosis.confidence) || 0,
            treatmentPlan: Array.isArray(result.treatmentPlan) ? result.treatmentPlan : [],
            scannedAt: new Date(),
          };
        }
        if (result.careAdvice) {
          const c = result.careAdvice;
          // ИИ задаёт базовый уход; ручные значения пользователя (если есть) важнее.
          doc.care = {
            wateringIntervalDays: c.wateringIntervalDays,
            waterAmountMl: c.waterAmountMl,
            light: c.light,
            fertilizerIntervalDays: c.fertilizerIntervalDays,
            temperature: c.temperature,
            ...(careObj || {}),
          };
        }
        if (Number.isFinite(Number(result.nextCheckupDays))) {
          const days = Math.round(Number(result.nextCheckupDays));
          doc.care = { ...(doc.care || {}), checkupIntervalDays: days };
          doc.nextCheckupAt = new Date(Date.now() + days * 86400000);
        }
      }
    } catch (err) {
      console.error('[plants.create] авто-анализ не удался:', err.message);
    }
  }

  const plant = await Plant.create(doc);

  await Reminder.create({
    userId: req.user._id,
    plantId: plant._id,
    type: 'watering',
    intervalDays: plant.care.wateringIntervalDays,
    nextDueAt: plant.wateringDueAt(),
  });

  res.status(201).json({ plant: plantView(plant) });
});

async function findOwnPlant(req, res) {
  const plant = await Plant.findOne({ _id: req.params.id, userId: req.user._id });
  if (!plant) {
    res.status(404).json({ error: 'Растение не найдено' });
    return null;
  }
  return plant;
}

router.get('/:id', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const [journal, reminders] = await Promise.all([
    JournalEntry.find({ plantId: plant._id }).sort({ createdAt: -1 }),
    Reminder.find({ plantId: plant._id, active: true }),
  ]);
  res.json({ plant: plantView(plant), journal, reminders });
});

router.patch('/:id', upload.single('photo'), async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;

  const { name, species, location, care } = req.body || {};
  if (name) plant.name = name;
  if (species !== undefined) plant.species = species;
  if (location) plant.location = location === 'outdoor' ? 'outdoor' : 'indoor';
  if (req.file) plant.photoUrl = await saveImage(req.file.buffer);
  if (care) {
    try {
      const careObj = typeof care === 'string' ? JSON.parse(care) : care;
      plant.care = { ...plant.care.toObject(), ...careObj };
      await Reminder.updateOne(
        { plantId: plant._id, type: 'watering' },
        { intervalDays: plant.care.wateringIntervalDays }
      );
    } catch {
      return res.status(400).json({ error: 'Некорректный формат care' });
    }
  }
  await plant.save();
  res.json({ plant: plantView(plant) });
});

router.delete('/:id', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  await Promise.all([
    plant.deleteOne(),
    JournalEntry.deleteMany({ plantId: plant._id }),
    Reminder.deleteMany({ plantId: plant._id }),
  ]);
  res.json({ ok: true });
});

router.post('/:id/water', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  plant.lastWateredAt = new Date();
  await plant.save();
  await Reminder.updateOne(
    { plantId: plant._id, type: 'watering' },
    { nextDueAt: plant.wateringDueAt() }
  );
  res.json({ plant: plantView(plant) });
});

router.post('/:id/fertilize', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  plant.lastFertilizedAt = new Date();
  await plant.save();
  res.json({ plant: plantView(plant) });
});

// Плановый ИИ-чекап: перефотографируем растение, ИИ сравнивает с прошлым
// состоянием, обновляет здоровье/диагноз/уход и пишет запись «до/после».
router.post('/:id/checkup', upload.single('photo'), async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  if (!req.file) return res.status(400).json({ error: 'Нужно фото для чекапа' });

  const note = (req.body && req.body.note) || '';
  const prevPhotoUrl = plant.photoUrl;
  const prevScore = typeof plant.healthScore === 'number' ? plant.healthScore : null;

  const [photoUrl, geminiJpeg] = await Promise.all([
    saveImage(req.file.buffer),
    toGeminiJpeg(req.file.buffer),
  ]);

  let result;
  try {
    result = await analyzePlantImage(geminiJpeg, {
      previousDiagnosis: plant.lastDiagnosis || null,
      plantContext: {
        name: plant.name,
        species: plant.species,
        location: plant.location,
        stage: plant.stage,
        plantedAt: plant.plantedAt,
      },
      mode: plant.origin === 'grown' ? 'grow' : 'diagnose',
    });
  } catch (err) {
    console.error('[checkup] gemini error:', err.message);
    return res.status(502).json({ error: 'ИИ временно недоступен, попробуйте ещё раз' });
  }

  const now = new Date();
  const entryData = {
    userId: req.user._id,
    plantId: plant._id,
    photoUrl,
    note,
    kind: 'progress',
  };

  if (result.isPlant) {
    const status = result.isHealthy
      ? 'thriving'
      : result.healthScore >= 55 ? 'needs_attention' : 'sick';
    entryData.healthScore = result.healthScore;
    entryData.healthStatus = status;
    entryData.analysis = result.progressNote || result.diagnosis?.description || '';
    if (prevScore != null) {
      entryData.trend =
        result.healthScore > prevScore + 2 ? 'up'
          : result.healthScore < prevScore - 2 ? 'down'
            : 'same';
    }

    plant.healthScore = result.healthScore;
    plant.healthStatus = status;
    plant.lastDiagnosis = {
      isHealthy: result.isHealthy,
      title: result.diagnosis?.title || '',
      description: result.diagnosis?.description || '',
      confidence: Number(result.diagnosis?.confidence) || 0,
      treatmentPlan: Array.isArray(result.treatmentPlan) ? result.treatmentPlan : [],
      scannedAt: now,
    };
    if (result.species) plant.species = result.species;
    const validStages = ['seed', 'sprout', 'seedling', 'growing', 'mature', 'flowering'];
    if (validStages.includes(result.growthStage)) plant.stage = result.growthStage;
    if (result.careAdvice) {
      const c = result.careAdvice;
      if (c.wateringIntervalDays) plant.care.wateringIntervalDays = c.wateringIntervalDays;
      if (c.waterAmountMl) plant.care.waterAmountMl = c.waterAmountMl;
      if (c.light) plant.care.light = c.light;
      if (c.fertilizerIntervalDays) plant.care.fertilizerIntervalDays = c.fertilizerIntervalDays;
      if (c.temperature) plant.care.temperature = c.temperature;
    }
    // Свежая фотка становится главной.
    plant.photoUrl = photoUrl;
  }

  // Планируем следующий чекап.
  const nextDays = result.nextCheckupDays || plant.care.checkupIntervalDays || 14;
  plant.care.checkupIntervalDays = nextDays;
  plant.lastCheckupAt = now;
  plant.nextCheckupAt = new Date(now.getTime() + nextDays * 86400000);
  plant.lastCheckupNotifiedAt = now;
  await plant.save();

  const entry = await JournalEntry.create(entryData);

  res.status(201).json({
    entry,
    plant: plantView(plant),
    result,
    previousPhotoUrl: prevPhotoUrl,
    growthAdvice: Array.isArray(result.growthAdvice) ? result.growthAdvice : [],
  });
});

// Журнал роста «до/после».
router.post('/:id/journal', upload.single('photo'), async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const { note, kind } = req.body || {};
  let photoUrl = null;
  if (req.file) photoUrl = await saveImage(req.file.buffer);
  if (!photoUrl && !note) return res.status(400).json({ error: 'Нужно фото или заметка' });

  const entryData = {
    userId: req.user._id,
    plantId: plant._id,
    photoUrl,
    note: note || '',
    kind: ['before', 'after', 'progress'].includes(kind) ? kind : 'progress',
  };

  // Если есть фото — ИИ оценивает состояние и обновляет health score растения.
  if (req.file) {
    try {
      const prevScore = plant.healthScore;
      const geminiJpeg = await toGeminiJpeg(req.file.buffer);
      const result = await analyzePlantImage(geminiJpeg, {
        previousDiagnosis: plant.lastDiagnosis || null,
      });
      if (result.isPlant) {
        entryData.healthScore = result.healthScore;
        entryData.healthStatus = result.isHealthy
          ? 'thriving'
          : result.healthScore >= 55
            ? 'needs_attention'
            : 'sick';
        entryData.analysis = result.progressNote || result.diagnosis?.description || '';
        if (typeof prevScore === 'number') {
          entryData.trend =
            result.healthScore > prevScore + 2
              ? 'up'
              : result.healthScore < prevScore - 2
                ? 'down'
                : 'same';
        }
        plant.healthScore = result.healthScore;
        plant.healthStatus = entryData.healthStatus;
        plant.lastDiagnosis = {
          isHealthy: result.isHealthy,
          title: result.diagnosis.title,
          description: result.diagnosis.description,
          confidence: result.diagnosis.confidence,
          treatmentPlan: result.treatmentPlan,
          scannedAt: new Date(),
        };
        if (!plant.species && result.species) plant.species = result.species;
        await plant.save();
      }
    } catch (err) {
      console.error('[journal] gemini error:', err.message);
      // Не роняем добавление записи, просто без ИИ-оценки.
    }
  }

  const entry = await JournalEntry.create(entryData);
  res.status(201).json({ entry, plant: plantView(plant) });
});

router.delete('/:id/journal/:entryId', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  await JournalEntry.deleteOne({ _id: req.params.entryId, plantId: plant._id });
  res.json({ ok: true });
});

// Напоминания растения.
router.get('/:id/reminders', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const reminders = await Reminder.find({ plantId: plant._id });
  res.json({ reminders });
});

router.post('/:id/reminders', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const { type, intervalDays } = req.body || {};
  if (!['watering', 'fertilizing'].includes(type) || !intervalDays) {
    return res.status(400).json({ error: 'Нужны type (watering|fertilizing) и intervalDays' });
  }
  const reminder = await Reminder.findOneAndUpdate(
    { plantId: plant._id, type },
    {
      userId: req.user._id,
      plantId: plant._id,
      type,
      intervalDays,
      nextDueAt: new Date(Date.now() + intervalDays * 86400000),
      active: true,
    },
    { upsert: true, new: true }
  );
  res.json({ reminder });
});

router.delete('/:id/reminders/:reminderId', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  await Reminder.updateOne({ _id: req.params.reminderId, plantId: plant._id }, { active: false });
  res.json({ ok: true });
});

export default router;
