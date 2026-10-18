import { Router } from 'express';
import mongoose from 'mongoose';
import { requireAuth } from '../middleware/auth.js';
import { upload, saveImage, toGeminiJpeg } from '../utils/upload.js';
import { analyzePlantImage } from '../services/gemini.js';
import { scanQuota, AnalysisError } from '../services/scanQuota.js';
import { Scan } from '../models/Scan.js';
import { Plant } from '../models/Plant.js';
import { JournalEntry } from '../models/JournalEntry.js';
import { applyPlantAnalysis, journalSnapshot } from '../utils/plantCare.js';
import { analysisOptions, ensureBaseline, ownPlantView, syncCareReminders } from '../services/plantProgress.js';

const router = Router();
router.use(requireAuth);

router.get('/quota', async (req, res) => {
  res.json(await scanQuota.view(req.user));
});

router.post('/', upload.single('image'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Нужно фото (поле image)' });
  let plant = null;
  if (req.body.plantId) {
    if (!mongoose.isValidObjectId(req.body.plantId)) return res.status(400).json({ error: 'Некорректный идентификатор растения' });
    plant = await Plant.findOne({ _id: req.body.plantId, userId: req.user._id });
    if (!plant) return res.status(404).json({ error: 'Растение не найдено' });
  }
  try {
    const jpeg = await toGeminiJpeg(req.file.buffer);
    const outcome = await scanQuota.run(req.user,
      () => analyzePlantImage(jpeg, plant ? analysisOptions(plant) : {}),
      async (result) => {
        const imageUrl = await saveImage(req.file.buffer);
        const scan = await Scan.create({ userId: req.user._id, plantId: plant?._id || null, imageUrl, result });
        if (plant) {
          const previousScore = plant.lastDiagnosis ? plant.healthScore : null;
          await ensureBaseline(plant);
          await JournalEntry.create({
            userId: req.user._id, plantId: plant._id, photoUrl: imageUrl, source: 'checkup', kind: 'progress',
            ...journalSnapshot(result, previousScore),
          });
          applyPlantAnalysis(plant, result, { photoUrl: imageUrl, now: scan.createdAt, scanId: scan._id });
          await plant.save();
          await syncCareReminders(plant);
        }
        return scan;
      }, { allowNonPlant: true });
    res.json({
      scanId: outcome.value?._id || '', imageUrl: outcome.value?.imageUrl || '', result: outcome.result,
      plant: plant ? await ownPlantView(plant) : null, quota: outcome.quota,
    });
  } catch (error) {
    if (error instanceof AnalysisError) return res.status(error.status).json({ error: error.message, code: error.code });
    console.error('[scan]', error.message);
    return res.status(502).json({ error: 'ИИ временно недоступен. Попробуйте ещё раз: скан не списан.' });
  }
});

router.get('/history', async (req, res) => {
  const scans = await Scan.find({ userId: req.user._id }).sort({ createdAt: -1 }).limit(50);
  res.json({ scans });
});

export default router;
