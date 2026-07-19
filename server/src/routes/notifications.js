import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { User } from '../models/User.js';
import { sendToUser, isPushEnabled } from '../services/push.js';

const router = Router();
router.use(requireAuth);

// Регистрация FCM-токена устройства (после входа в приложение).
router.post('/token', async (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: 'Нужен token' });
  await User.updateOne({ _id: req.user._id }, { $addToSet: { fcmTokens: token } });
  res.json({ ok: true, pushEnabled: isPushEnabled() });
});

// Удаление токена (при выходе из аккаунта).
router.delete('/token', async (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: 'Нужен token' });
  await User.updateOne({ _id: req.user._id }, { $pull: { fcmTokens: token } });
  res.json({ ok: true });
});

// Тестовый пуш самому себе — удобно проверить настройку.
router.post('/test', async (req, res) => {
  const result = await sendToUser(req.user._id, {
    title: 'Sprout AI 🌿',
    body: 'Тестовое уведомление работает!',
    data: { type: 'test' },
  });
  res.json(result);
});

export default router;
