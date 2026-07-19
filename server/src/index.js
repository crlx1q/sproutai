import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from './config.js';
import { connectDb } from './db.js';
import { uploadsDir } from './utils/upload.js';
import { printBanner } from './utils/banner.js';
import authRoutes from './routes/auth.js';
import plantRoutes from './routes/plants.js';
import scanRoutes from './routes/scan.js';
import communityRoutes from './routes/community.js';
import adminRoutes from './routes/admin.js';
import notificationsRoutes from './routes/notifications.js';
import { initPush } from './services/push.js';
import { startReminderScheduler } from './services/scheduler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.resolve(__dirname, '../public');

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.use('/uploads', express.static(uploadsDir, { maxAge: '30d' }));
app.use(express.static(publicDir));

app.get('/api/health', (req, res) => res.json({ ok: true, ts: Date.now() }));
app.use('/api/auth', authRoutes);
app.use('/api/plants', plantRoutes);
app.use('/api/scan', scanRoutes);
app.use('/api/community', communityRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/notifications', notificationsRoutes);

app.get('/admin', (req, res) => res.sendFile(path.join(publicDir, 'admin', 'index.html')));

app.use((err, req, res, next) => {
  console.error('[error]', err);
  res.status(500).json({ error: 'Внутренняя ошибка сервера' });
});

connectDb()
  .then(() => {
    initPush();
    startReminderScheduler();
    app.listen(config.port, '0.0.0.0', () => printBanner(config.port));
  })
  .catch((err) => {
    console.error('[db] connection failed:', err.message);
    process.exit(1);
  });
