import { Router } from 'express';
import { requireAuth, requireAdmin } from '../middleware/auth.js';
import { User } from '../models/User.js';
import { Plant } from '../models/Plant.js';
import { Scan } from '../models/Scan.js';
import { Post } from '../models/Post.js';
import { Comment } from '../models/Comment.js';

const router = Router();
router.use(requireAuth, requireAdmin);

router.get('/stats', async (req, res) => {
  const since = new Date(Date.now() - 30 * 86400000);
  const [users, proUsers, plants, scans, posts, regByDay, scansByDay] = await Promise.all([
    User.countDocuments(),
    User.countDocuments({ plan: 'pro' }),
    Plant.countDocuments(),
    Scan.countDocuments(),
    Post.countDocuments(),
    User.aggregate([
      { $match: { createdAt: { $gte: since } } },
      { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } }, count: { $sum: 1 } } },
      { $sort: { _id: 1 } },
    ]),
    Scan.aggregate([
      { $match: { createdAt: { $gte: since } } },
      { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } }, count: { $sum: 1 } } },
      { $sort: { _id: 1 } },
    ]),
  ]);
  res.json({ users, proUsers, plants, scans, posts, regByDay, scansByDay });
});

router.get('/users', async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = 25;
  const q = (req.query.q || '').trim();
  const filter = q
    ? { $or: [{ email: { $regex: q, $options: 'i' } }, { name: { $regex: q, $options: 'i' } }] }
    : {};
  const [items, total] = await Promise.all([
    User.find(filter).sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit),
    User.countDocuments(filter),
  ]);
  res.json({
    users: items.map((u) => ({
      ...u.toPublic(),
      isBlocked: u.isBlocked,
      scansUsed: u.scansUsed,
    })),
    total,
    page,
    pages: Math.ceil(total / limit),
  });
});

router.patch('/users/:id', async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });

  const { plan, proUntil, isBlocked } = req.body || {};
  if (plan && ['free', 'pro'].includes(plan)) {
    user.plan = plan;
    if (plan === 'free') user.proUntil = null;
  }
  if (proUntil !== undefined) user.proUntil = proUntil ? new Date(proUntil) : null;
  if (typeof isBlocked === 'boolean' && user.role !== 'admin') user.isBlocked = isBlocked;
  await user.save();
  res.json({ user: { ...user.toPublic(), isBlocked: user.isBlocked } });
});

router.get('/scans', async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = 25;
  const [scans, total] = await Promise.all([
    Scan.find().sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).populate('userId', 'email name'),
    Scan.countDocuments(),
  ]);
  res.json({ scans, total, page, pages: Math.ceil(total / limit) });
});

router.get('/posts', async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = 25;
  const [posts, total] = await Promise.all([
    Post.find().sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).populate('userId', 'email name'),
    Post.countDocuments(),
  ]);
  res.json({ posts, total, page, pages: Math.ceil(total / limit) });
});

router.delete('/posts/:id', async (req, res) => {
  await Promise.all([
    Post.deleteOne({ _id: req.params.id }),
    Comment.deleteMany({ postId: req.params.id }),
  ]);
  res.json({ ok: true });
});

export default router;
