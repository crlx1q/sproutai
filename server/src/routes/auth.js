import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { User } from '../models/User.js';
import { config } from '../config.js';
import { requireAuth, signTokens } from '../middleware/auth.js';
import { upload, saveImage } from '../utils/upload.js';

const router = Router();

router.post('/register', async (req, res) => {
  const { email, password, name } = req.body || {};
  if (!email || !password || !name) {
    return res.status(400).json({ error: 'Нужны email, password и name' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Пароль минимум 6 символов' });
  }
  const exists = await User.findOne({ email: email.toLowerCase().trim() });
  if (exists) return res.status(409).json({ error: 'Email уже зарегистрирован' });

  const user = await User.create({
    email,
    name,
    passwordHash: await bcrypt.hash(password, 10),
  });
  const tokens = signTokens(user);
  res.status(201).json({ user: user.toPublic(), ...tokens });
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  const user = await User.findOne({ email: (email || '').toLowerCase().trim() });
  if (!user || !(await bcrypt.compare(password || '', user.passwordHash))) {
    return res.status(401).json({ error: 'Неверный email или пароль' });
  }
  if (user.isBlocked) return res.status(403).json({ error: 'Аккаунт заблокирован' });
  const tokens = signTokens(user);
  res.json({ user: user.toPublic(), ...tokens });
});

router.post('/refresh', async (req, res) => {
  const { refreshToken } = req.body || {};
  if (!refreshToken) return res.status(400).json({ error: 'Нужен refreshToken' });
  try {
    const payload = jwt.verify(refreshToken, config.jwtRefreshSecret);
    const user = await User.findById(payload.sub);
    if (!user || user.isBlocked) return res.status(401).json({ error: 'Недействительный токен' });
    const tokens = signTokens(user);
    res.json({ user: user.toPublic(), ...tokens });
  } catch {
    res.status(401).json({ error: 'Недействительный токен' });
  }
});

router.get('/me', requireAuth, async (req, res) => {
  res.json({ user: req.user.toPublic() });
});

router.patch('/me', requireAuth, upload.single('avatar'), async (req, res) => {
  const { name } = req.body || {};
  if (name) req.user.name = name;
  if (req.file) req.user.avatarUrl = await saveImage(req.file.buffer, { maxSize: 512 });
  await req.user.save();
  res.json({ user: req.user.toPublic() });
});

export default router;
