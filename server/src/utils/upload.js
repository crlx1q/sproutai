import multer from 'multer';
import sharp from 'sharp';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const uploadsDir = path.resolve(__dirname, '../../uploads');
fs.mkdirSync(uploadsDir, { recursive: true });

export const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    cb(null, /^image\//.test(file.mimetype));
  },
});

// Сжимает изображение и сохраняет в uploads/, возвращает публичный URL-путь.
export async function saveImage(buffer, { maxSize = 1280 } = {}) {
  const name = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.jpg`;
  await sharp(buffer)
    .rotate()
    .resize(maxSize, maxSize, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 82 })
    .toFile(path.join(uploadsDir, name));
  return `/uploads/${name}`;
}

// Уменьшенная копия для отправки в Gemini (меньше токенов).
export async function toGeminiJpeg(buffer) {
  return sharp(buffer)
    .rotate()
    .resize(768, 768, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 78 })
    .toBuffer();
}
