import { Router } from 'express';
import mongoose from 'mongoose';
import { requireAuth } from '../middleware/auth.js';
import { upload, saveImage, toGeminiJpeg } from '../utils/upload.js';
import { analyzePlantImage } from '../services/gemini.js';
import { scanQuota, AnalysisError } from '../services/scanQuota.js';
import { Plant } from '../models/Plant.js';
import { JournalEntry } from '../models/JournalEntry.js';
import { Reminder } from '../models/Reminder.js';
import { Scan } from '../models/Scan.js';
import { plantView, ownPlantView, syncCareReminders, ensureBaseline, analysisOptions, baselineData } from '../services/plantProgress.js';
import { DAY_MS, CHECKUP_DAYS, GROWTH_STAGES, applyPlantAnalysis, asDate, buildWeeklyHistory, changedCareFields, journalSnapshot, validateCare } from '../utils/plantCare.js';

const router = Router();
router.use(requireAuth);

function parseMaybe(value) {
  if (value === undefined || value === null || value === '') return undefined;
  return typeof value === 'string' ? JSON.parse(value) : value;
}

function sendAnalysisError(res, error) {
  if (error instanceof AnalysisError) return res.status(error.status).json({ error: error.message, code: error.code });
  console.error('[plant analysis]', error.message);
  return res.status(502).json({ error: 'Не удалось сохранить анализ. Попробуйте ещё раз: скан не списан.' });
}

router.get('/', async (req, res) => {
  const plants = await Plant.find({ userId: req.user._id }).sort({ createdAt: -1 });
  const reminders = await Reminder.find({ userId: req.user._id });
  res.json({ plants: plants.map((p) => plantView(p, reminders)) });
});

router.get('/tasks/today', async (req, res) => {
  const plants = await Plant.find({ userId: req.user._id });
  const reminders = await Reminder.find({ userId: req.user._id });
  const views = plants.map((p) => plantView(p, reminders));
  const needWater = views.filter((p) => p.needsWater);
  const needFertilizer = views.filter((p) => p.needsFertilizer);
  const needCheckup = views.filter((p) => p.needsCheckup);
  res.json({ needWater, needFertilizer, needCheckup, count: needWater.length + needFertilizer.length + needCheckup.length });
});

router.post('/water-all', async (req, res) => {
  const plants = await Plant.find({ userId: req.user._id });
  const now = new Date();
  const due = plants.filter((p) => p.wateringDueAt() <= now);
  for (const plant of due) {
    plant.lastWateredAt = now;
    plant.wateringSnoozedUntil = null;
    plant.lastWaterNotifiedAt = null;
    plant.lastWaterDeliveredAt = null;
    await plant.save();
    await syncCareReminders(plant);
  }
  res.json({ watered: due.length });
});

router.post('/', upload.single('photo'), async (req, res) => {
  const body = req.body || {};
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (!name || name.length > 100) return res.status(400).json({ error: 'Укажите имя растения до 100 символов' });
  let care;
  try { care = body.care ? validateCare(parseMaybe(body.care)) : { checkupIntervalDays: CHECKUP_DAYS }; }
  catch (error) { return res.status(400).json({ error: error.message }); }
  const plantedAt = body.plantedAt ? asDate(body.plantedAt) : null;
  if (body.plantedAt && !plantedAt) return res.status(400).json({ error: 'Некорректная дата посадки' });
  const grown = body.origin === 'grown';
  const doc = {
    userId: req.user._id, name, species: String(body.species || '').trim().slice(0, 200),
    location: body.location === 'outdoor' ? 'outdoor' : 'indoor', origin: grown ? 'grown' : 'existing',
    stage: GROWTH_STAGES.includes(body.stage) ? body.stage : grown ? 'seedling' : 'mature',
    plantedAt: plantedAt || (grown ? new Date() : null), growthGoal: String(body.growthGoal || '').slice(0, 2000),
    photoUrl: typeof body.photoUrl === 'string' ? body.photoUrl : null, care: { ...care },
    careManualFields: changedCareFields({}, care), lastWateredAt: new Date(),
  };
  let sourceScan = null;
  if (body.scanId) {
    if (!mongoose.isValidObjectId(body.scanId)) return res.status(400).json({ error: 'Некорректный скан' });
    sourceScan = await Scan.findOne({ _id: body.scanId, userId: req.user._id });
    if (!sourceScan?.result?.isPlant) return res.status(404).json({ error: 'Скан растения не найден' });
    if (sourceScan.plantId) return res.status(409).json({ error: 'Этот скан уже сохранён в сад' });
    doc.photoUrl = sourceScan.imageUrl;
  }
  async function persist(result) {
    if (result) {
      if (req.file && !sourceScan) doc.photoUrl = await saveImage(req.file.buffer);
      applyPlantAnalysis(doc, result, { photoUrl: doc.photoUrl, scanId: sourceScan?._id });
      doc.care = { ...doc.care, ...care };
    }
    const plant = await Plant.create(doc);
    if (sourceScan) {
      const linked = await Scan.updateOne({ _id: sourceScan._id, plantId: null }, { $set: { plantId: plant._id } });
      if (!linked.modifiedCount) {
        await plant.deleteOne();
        throw new AnalysisError('Этот скан уже сохранён в сад', 409, 'SCAN_ALREADY_SAVED');
      }
    }
    await ensureBaseline(plant);
    await syncCareReminders(plant);
    return plant;
  }
  try {
    let plant;
    let quota;
    if (req.file && !sourceScan) {
      const jpeg = await toGeminiJpeg(req.file.buffer);
      const outcome = await scanQuota.run(req.user, () => analyzePlantImage(jpeg, {
        plantContext: doc, mode: grown ? 'grow' : 'diagnose',
      }), persist);
      plant = outcome.value;
      quota = outcome.quota;
    } else {
      plant = await persist(sourceScan?.result || null);
    }
    res.status(201).json({ plant: await ownPlantView(plant), ...(quota ? { quota } : {}) });
  } catch (error) { return sendAnalysisError(res, error); }
});

async function findOwnPlant(req, res) {
  if (!mongoose.isValidObjectId(req.params.id)) {
    res.status(400).json({ error: 'Некорректный идентификатор растения' });
    return null;
  }
  const plant = await Plant.findOne({ _id: req.params.id, userId: req.user._id });
  if (!plant) res.status(404).json({ error: 'Растение не найдено' });
  return plant;
}

router.get('/:id', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const [documents, reminders] = await Promise.all([
    JournalEntry.find({ plantId: plant._id }).sort({ createdAt: -1 }),
    Reminder.find({ plantId: plant._id }),
  ]);
  const journal = documents.map((entry) => entry.toObject());
  // Existing plants get a virtual initial frame until the next accepted photo persists it.
  if (plant.photoUrl && !journal.some((entry) => entry.source === 'baseline' || entry.photoUrl === plant.photoUrl)) {
    journal.push({ ...baselineData(plant), _id: `baseline-${plant._id}`, updatedAt: plant.createdAt });
    journal.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }
  res.json({ plant: plantView(plant, reminders), journal, reminders: reminders.filter((r) => r.active), weeklyHistory: buildWeeklyHistory(plant, journal) });
});

router.patch('/:id', upload.single('photo'), async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const { name, species, location, care } = req.body || {};
  if (name !== undefined) {
    if (typeof name !== 'string' || !name.trim() || name.trim().length > 100) return res.status(400).json({ error: 'Укажите имя растения до 100 символов' });
    plant.name = name.trim();
  }
  if (species !== undefined) plant.species = String(species).trim().slice(0, 200);
  if (location) plant.location = location === 'outdoor' ? 'outdoor' : 'indoor';
  if (care) {
    try {
      const updates = validateCare(parseMaybe(care));
      plant.careManualFields = [...new Set([...plant.careManualFields, ...changedCareFields(plant.care, updates)])];
      plant.care = { ...plant.care.toObject(), ...updates };
    }
    catch (error) { return res.status(400).json({ error: error.message }); }
  }
  if (req.file) {
    await ensureBaseline(plant);
    plant.photoUrl = await saveImage(req.file.buffer);
    await JournalEntry.create({ userId: req.user._id, plantId: plant._id, photoUrl: plant.photoUrl, note: 'Обновлено фото растения', source: 'journal' });
  }
  await plant.save();
  await syncCareReminders(plant);
  res.json({ plant: await ownPlantView(plant) });
});

router.delete('/:id', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  await Promise.all([
    plant.deleteOne(), JournalEntry.deleteMany({ plantId: plant._id }), Reminder.deleteMany({ plantId: plant._id }),
    Scan.updateMany({ plantId: plant._id, userId: req.user._id }, { $set: { plantId: null } }),
  ]);
  res.json({ ok: true });
});

for (const [action, timestamp, snoozed, notified] of [
  ['water', 'lastWateredAt', 'wateringSnoozedUntil', 'lastWaterNotifiedAt'],
  ['fertilize', 'lastFertilizedAt', 'fertilizingSnoozedUntil', 'lastFertilizeNotifiedAt'],
]) {
  router.post(`/:id/${action}`, async (req, res) => {
    const plant = await findOwnPlant(req, res);
    if (!plant) return;
    plant[timestamp] = new Date();
    plant[snoozed] = null;
    plant[notified] = null;
    plant[action === 'water' ? 'lastWaterDeliveredAt' : 'lastFertilizeDeliveredAt'] = null;
    await plant.save();
    await syncCareReminders(plant);
    res.json({ plant: await ownPlantView(plant) });
  });
}

router.post('/:id/care/snooze', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const type = req.body?.type;
  const days = Number(req.body?.days ?? 1);
  if (!['watering', 'fertilizing'].includes(type) || !Number.isInteger(days) || days < 1 || days > 30) {
    return res.status(400).json({ error: 'Укажите тип ухода и срок переноса от 1 до 30 дней' });
  }
  plant[type === 'watering' ? 'wateringSnoozedUntil' : 'fertilizingSnoozedUntil'] = new Date(Date.now() + days * DAY_MS);
  await plant.save();
  await syncCareReminders(plant);
  res.json({ plant: await ownPlantView(plant) });
});

async function recordObservation(req, res, plant, source) {
  const note = String(req.body?.note || '').trim().slice(0, 5000);
  const kind = ['before', 'after', 'progress'].includes(req.body?.kind) ? req.body.kind : 'progress';
  const previousPhotoUrl = plant.photoUrl;
  try {
    const jpeg = await toGeminiJpeg(req.file.buffer);
    const outcome = await scanQuota.run(req.user, () => analyzePlantImage(jpeg, analysisOptions(plant)), async (result) => {
      const previousScore = plant.lastDiagnosis ? plant.healthScore : null;
      await ensureBaseline(plant);
      const photoUrl = await saveImage(req.file.buffer);
      const entry = await JournalEntry.create({
        userId: req.user._id, plantId: plant._id, photoUrl, note, kind, source,
        ...journalSnapshot(result, previousScore),
      });
      applyPlantAnalysis(plant, result, { photoUrl, now: entry.createdAt });
      await plant.save();
      await syncCareReminders(plant);
      return entry;
    });
    res.status(201).json({
      entry: outcome.value, plant: await ownPlantView(plant), result: outcome.result, quota: outcome.quota,
      previousPhotoUrl, growthAdvice: outcome.result.growthAdvice || [],
    });
  } catch (error) { return sendAnalysisError(res, error); }
}

router.post('/:id/checkup', upload.single('photo'), async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  if (!req.file) return res.status(400).json({ error: 'Нужно фото для проверки' });
  return recordObservation(req, res, plant, 'checkup');
});

router.post('/:id/journal', upload.single('photo'), async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  if (req.file && req.body?.analyze !== false && req.body?.analyze !== 'false') return recordObservation(req, res, plant, 'journal');
  const note = String(req.body?.note || '').trim().slice(0, 5000);
  if (!note && !req.file) return res.status(400).json({ error: 'Нужно фото или заметка' });
  const kind = ['before', 'after', 'progress'].includes(req.body?.kind) ? req.body.kind : 'progress';
  const photoUrl = req.file ? await saveImage(req.file.buffer) : null;
  const entry = await JournalEntry.create({ userId: req.user._id, plantId: plant._id, photoUrl, note, kind, source: 'journal' });
  res.status(201).json({ entry, plant: await ownPlantView(plant) });
});

router.delete('/:id/journal/:entryId', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  if (!mongoose.isValidObjectId(req.params.entryId)) return res.status(400).json({ error: 'Некорректная запись' });
  await JournalEntry.deleteOne({ _id: req.params.entryId, plantId: plant._id });
  res.json({ ok: true });
});

router.get('/:id/reminders', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  res.json({ reminders: await Reminder.find({ plantId: plant._id }) });
});

router.post('/:id/reminders', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  const type = req.body?.type;
  const intervalDays = type === 'checkup' ? CHECKUP_DAYS : Number(req.body?.intervalDays);
  if (!['watering', 'fertilizing', 'checkup'].includes(type) || !Number.isInteger(intervalDays) || intervalDays < 1 || intervalDays > 365) {
    return res.status(400).json({ error: 'Укажите тип напоминания и интервал от 1 до 365 дней' });
  }
  const careField = type === 'watering' ? 'wateringIntervalDays' : type === 'fertilizing' ? 'fertilizerIntervalDays' : null;
  if (careField) {
    if (plant.care[careField] !== intervalDays) plant.careManualFields = [...new Set([...plant.careManualFields, careField])];
    plant.care[careField] = intervalDays;
  }
  plant.care.checkupIntervalDays = CHECKUP_DAYS;
  await plant.save();
  await syncCareReminders(plant);
  const reminder = await Reminder.findOneAndUpdate({ plantId: plant._id, type }, { $set: { active: true } }, { new: true });
  res.json({ reminder, plant: await ownPlantView(plant) });
});

router.delete('/:id/reminders/:reminderId', async (req, res) => {
  const plant = await findOwnPlant(req, res);
  if (!plant) return;
  if (!mongoose.isValidObjectId(req.params.reminderId)) return res.status(400).json({ error: 'Некорректное напоминание' });
  await Reminder.updateOne({ _id: req.params.reminderId, plantId: plant._id }, { $set: { active: false } });
  res.json({ ok: true, plant: await ownPlantView(plant) });
});

export default router;
