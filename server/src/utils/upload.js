import multer from 'multer';
import sharp from 'sharp';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import { v2 as cloudinary } from 'cloudinary';
import { config } from '../config.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const uploadsDir = path.resolve(__dirname, '../../uploads');
fs.mkdirSync(uploadsDir, { recursive: true });

// Cloudinary включается автоматически, если в окружении заданы креды.
const cloudinaryReady = Boolean(
  config.cloudinary.cloudName &&
    config.cloudinary.apiKey &&
    config.cloudinary.apiSecret,
);

if (cloudinaryReady) {
  cloudinary.config({
    cloud_name: config.cloudinary.cloudName,
    api_key: config.cloudinary.apiKey,
    api_secret: config.cloudinary.apiSecret,
    secure: true,
  });
  console.log('[upload] Cloudinary storage enabled');
} else {
  console.log(
    '[upload] Cloudinary не настроен — сохраняю на локальный диск (только для разработки)',
  );
}

/// Храним ли картинки в облаке (Cloudinary) или на диске.
export const isCloudStorage = () => cloudinaryReady;

export const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    cb(null, /^image\//.test(file.mimetype));
  },
});

function uploadBufferToCloudinary(buffer) {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      { folder: 'sproutai', resource_type: 'image', format: 'jpg' },
      (err, result) => (err ? reject(err) : resolve(result)),
    );
    stream.end(buffer);
  });
}

// Сжимает изображение и сохраняет: в Cloudinary (прод) или на диск (dev).
// Возвращает публичный URL: абсолютный https (Cloudinary) или /uploads/... (диск).
export async function saveImage(buffer, { maxSize = 1280 } = {}) {
  const processed = await sharp(buffer)
    .rotate()
    .resize(maxSize, maxSize, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 82 })
    .toBuffer();

  if (cloudinaryReady) {
    const res = await uploadBufferToCloudinary(processed);
    return res.secure_url;
  }

  const name = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.jpg`;
  await fs.promises.writeFile(path.join(uploadsDir, name), processed);
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
