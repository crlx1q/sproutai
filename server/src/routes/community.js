import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { upload, saveImage } from '../utils/upload.js';
import { Post } from '../models/Post.js';
import { Comment } from '../models/Comment.js';

const router = Router();
router.use(requireAuth);

function postView(post, userId) {
  return {
    id: post._id,
    author: post.userId
      ? { id: post.userId._id, name: post.userId.name, avatarUrl: post.userId.avatarUrl }
      : null,
    imageUrl: post.imageUrl,
    text: post.text,
    likesCount: post.likes.length,
    likedByMe: post.likes.some((id) => id.equals(userId)),
    commentsCount: post.commentsCount,
    createdAt: post.createdAt,
  };
}

router.get('/posts', async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = 20;
  const posts = await Post.find()
    .sort({ createdAt: -1 })
    .skip((page - 1) * limit)
    .limit(limit)
    .populate('userId', 'name avatarUrl');
  // Прячем «осиротевшие» посты (автор удалён) — именно они показывались без ника/аватара.
  const visible = posts.filter((p) => p.userId);
  res.json({ posts: visible.map((p) => postView(p, req.user._id)), page });
});

router.post('/posts', upload.single('image'), async (req, res) => {
  const { text, plantId } = req.body || {};
  if (!text) return res.status(400).json({ error: 'Нужен текст поста' });
  let imageUrl = null;
  if (req.file) imageUrl = await saveImage(req.file.buffer);

  const post = await Post.create({
    userId: req.user._id,
    plantId: plantId || null,
    imageUrl,
    text,
  });
  await post.populate('userId', 'name avatarUrl');
  res.status(201).json({ post: postView(post, req.user._id) });
});

router.delete('/posts/:id', async (req, res) => {
  const post = await Post.findOne({ _id: req.params.id, userId: req.user._id });
  if (!post) return res.status(404).json({ error: 'Пост не найден' });
  await Promise.all([post.deleteOne(), Comment.deleteMany({ postId: post._id })]);
  res.json({ ok: true });
});

router.post('/posts/:id/like', async (req, res) => {
  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ error: 'Пост не найден' });
  const idx = post.likes.findIndex((id) => id.equals(req.user._id));
  if (idx >= 0) post.likes.splice(idx, 1);
  else post.likes.push(req.user._id);
  await post.save();
  res.json({ likesCount: post.likes.length, likedByMe: idx < 0 });
});

router.get('/posts/:id/comments', async (req, res) => {
  const comments = await Comment.find({ postId: req.params.id })
    .sort({ createdAt: 1 })
    .populate('userId', 'name avatarUrl');
  res.json({
    comments: comments.map((c) => ({
      id: c._id,
      author: c.userId ? { id: c.userId._id, name: c.userId.name, avatarUrl: c.userId.avatarUrl } : null,
      text: c.text,
      createdAt: c.createdAt,
    })),
  });
});

router.post('/posts/:id/comments', async (req, res) => {
  const { text } = req.body || {};
  if (!text) return res.status(400).json({ error: 'Нужен текст комментария' });
  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ error: 'Пост не найден' });

  const comment = await Comment.create({ postId: post._id, userId: req.user._id, text });
  post.commentsCount += 1;
  await post.save();
  await comment.populate('userId', 'name avatarUrl');
  res.status(201).json({
    comment: {
      id: comment._id,
      author: { id: comment.userId._id, name: comment.userId.name, avatarUrl: comment.userId.avatarUrl },
      text: comment.text,
      createdAt: comment.createdAt,
    },
  });
});

export default router;
