import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { User } from '../models/User.js';
import { sendToUser, isPushEnabled, getPushStatus } from '../services/push.js';

const router = Router();
router.use(requireAuth);

function validToken(token) {
  return typeof token === 'string' && token.length >= 16 && token.length <= 4096 && !/\s/.test(token);
}

router.get('/status', async (req, res) => {
  const user = await User.findById(req.user._id).select('fcmTokens');
  res.json({ ...getPushStatus(), registeredDevices: user?.fcmTokens?.length || 0 });
});

// Регистрация FCM-токена устройства (после входа в приложение).
router.post('/token', async (req, res) => {
  const { token } = req.body || {};
  if (!validToken(token)) return res.status(400).json({ error: 'Неверный token устройства' });
  // A shared phone must stop receiving the previous account's plant reminders.
  await User.updateMany({ _id: { $ne: req.user._id }, fcmTokens: token }, { $pull: { fcmTokens: token } });
  await User.updateOne({ _id: req.user._id }, { $addToSet: { fcmTokens: token } });
  res.json({ ok: true, pushEnabled: isPushEnabled() });
});

// Удаление токена (при выходе из аккаунта).
router.delete('/token', async (req, res) => {
  const { token } = req.body || {};
  if (!validToken(token)) return res.status(400).json({ error: 'Неверный token устройства' });
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
