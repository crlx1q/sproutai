import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { upload, saveImage, toGeminiJpeg } from '../utils/upload.js';
import { analyzePlantImage } from '../services/gemini.js';
import { Scan } from '../models/Scan.js';
import { Plant } from '../models/Plant.js';
import { config } from '../config.js';

const router = Router();
router.use(requireAuth);

function isPro(user) {
  return user.plan === 'pro' && (!user.proUntil || user.proUntil > new Date());
}

function resetPeriodIfNeeded(user) {
  const monthMs = 30 * 86400000;
  if (Date.now() - user.scansPeriodStart.getTime() > monthMs) {
    user.scansUsed = 0;
    user.scansPeriodStart = new Date();
  }
}

router.get('/quota', async (req, res) => {
  resetPeriodIfNeeded(req.user);
  await req.user.save();
  const pro = isPro(req.user);
  res.json({
    plan: pro ? 'pro' : 'free',
    limit: pro ? null : config.freeScansPerMonth,
    used: req.user.scansUsed,
    remaining: pro ? null : Math.max(0, config.freeScansPerMonth - req.user.scansUsed),
  });
});

router.post('/', upload.single('image'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Нужно фото (поле image)' });

  const user = req.user;
  resetPeriodIfNeeded(user);
  const pro = isPro(user);
  if (!pro && user.scansUsed >= config.freeScansPerMonth) {
    return res.status(402).json({
      error: 'Лимит бесплатных сканов исчерпан. Оформите Pro для безлимита.',
      code: 'SCAN_LIMIT',
    });
  }

  let plant = null;
  if (req.body.plantId) {
    plant = await Plant.findOne({ _id: req.body.plantId, userId: user._id });
    if (!plant) return res.status(404).json({ error: 'Растение не найдено' });
  }

  const [imageUrl, geminiJpeg] = await Promise.all([
    saveImage(req.file.buffer),
    toGeminiJpeg(req.file.buffer),
  ]);

  let result;
  try {
    result = await analyzePlantImage(geminiJpeg, {
      previousDiagnosis: plant?.lastDiagnosis || null,
    });
  } catch (err) {
    console.error('[scan] gemini error:', err.message);
    return res.status(502).json({ error: 'ИИ временно недоступен, попробуйте ещё раз' });
  }

  const scan = await Scan.create({
    userId: user._id,
    plantId: plant?._id || null,
    imageUrl,
    result,
  });

  user.scansUsed += 1;
  await user.save();

  if (plant && result.isPlant) {
    plant.lastDiagnosis = {
      isHealthy: result.isHealthy,
      title: result.diagnosis.title,
      description: result.diagnosis.description,
      confidence: result.diagnosis.confidence,
      treatmentPlan: result.treatmentPlan,
      scanId: scan._id,
      scannedAt: new Date(),
    };
    plant.healthScore = result.healthScore;
    plant.healthStatus = result.isHealthy
      ? 'thriving'
      : result.healthScore >= 55
        ? 'needs_attention'
        : 'sick';
    if (!plant.species && result.species) plant.species = result.species;
    await plant.save();
  }

  res.json({
    scanId: scan._id,
    imageUrl,
    result,
    plant: plant || null,
    quota: {
      remaining: pro ? null : Math.max(0, config.freeScansPerMonth - user.scansUsed),
    },
  });
});

router.get('/history', async (req, res) => {
  const scans = await Scan.find({ userId: req.user._id }).sort({ createdAt: -1 }).limit(50);
  res.json({ scans });
});

export default router;
