import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { User } from '../models/User.js';

export async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Требуется авторизация' });

  try {
    const payload = jwt.verify(token, config.jwtSecret);
    const user = await User.findById(payload.sub);
    if (!user) return res.status(401).json({ error: 'Пользователь не найден' });
    if (user.isBlocked) return res.status(403).json({ error: 'Аккаунт заблокирован' });
    req.user = user;
    next();
  } catch {
    return res.status(401).json({ error: 'Недействительный токен' });
  }
}

export function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Доступ только для администратора' });
  }
  next();
}

export function signTokens(user) {
  const accessToken = jwt.sign({ sub: user._id.toString(), role: user.role }, config.jwtSecret, {
    expiresIn: config.accessTokenTtl,
  });
  const refreshToken = jwt.sign({ sub: user._id.toString() }, config.jwtRefreshSecret, {
    expiresIn: config.refreshTokenTtl,
  });
  return { accessToken, refreshToken };
}
