// Разовая миграция локальных картинок из uploads/ в Cloudinary.
//
// Запуск (из папки server, где лежит .env с кредами и рядом папка uploads/):
//   npm install          # чтобы подтянулся cloudinary
//   node scripts/migrate-uploads-to-cloudinary.js
//
// Скрипт находит в БД все документы с картинкой вида /uploads/xxx.jpg,
// загружает файл в Cloudinary и заменяет ссылку на постоянный https-URL.
// Безопасно запускать повторно: уже перенесённые (https://) ссылки не трогаются.
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import mongoose from 'mongoose';
import { v2 as cloudinary } from 'cloudinary';

import { config } from '../src/config.js';
import { uploadsDir } from '../src/utils/upload.js';
import { Plant } from '../src/models/Plant.js';
import { Scan } from '../src/models/Scan.js';
import { User } from '../src/models/User.js';
import { Post } from '../src/models/Post.js';
import { JournalEntry } from '../src/models/JournalEntry.js';

const { cloudName, apiKey, apiSecret } = config.cloudinary;
if (!cloudName || !apiKey || !apiSecret) {
  console.error('❌ Cloudinary креды не заданы. Добавьте CLOUDINARY_* в .env');
  process.exit(1);
}
cloudinary.config({
  cloud_name: cloudName,
  api_key: apiKey,
  api_secret: apiSecret,
  secure: true,
});

// Кэш: один локальный файл -> один Cloudinary URL (не грузим дубли).
const cache = new Map();
let uploaded = 0;
let updated = 0;
let missing = 0;

async function resolveUrl(rel) {
  if (cache.has(rel)) return cache.get(rel);
  const localPath = path.join(uploadsDir, rel.replace(/^\/uploads\//, ''));
  if (!fs.existsSync(localPath)) {
    missing++;
    console.warn('  ⚠ файл не найден локально:', localPath);
    return null;
  }
  const res = await cloudinary.uploader.upload(localPath, {
    folder: 'sproutai',
    resource_type: 'image',
  });
  uploaded++;
  cache.set(rel, res.secure_url);
  return res.secure_url;
}

async function migrateField(Model, field) {
  const label = `${Model.modelName}.${field}`;
  const docs = await Model.find({ [field]: { $regex: '^/uploads/' } }).select(
    `_id ${field}`,
  );
  console.log(`\n▶ ${label}: найдено ${docs.length} записей`);
  for (const doc of docs) {
    const url = await resolveUrl(doc[field]);
    if (!url) continue;
    await Model.updateOne({ _id: doc._id }, { $set: { [field]: url } });
    updated++;
    console.log(`  ✓ ${label} ${doc._id}`);
  }
}

async function main() {
  await mongoose.connect(config.mongoUri);
  console.log('[db] подключено к MongoDB');

  await migrateField(Plant, 'photoUrl');
  await migrateField(Scan, 'imageUrl');
  await migrateField(User, 'avatarUrl');
  await migrateField(Post, 'imageUrl');
  await migrateField(JournalEntry, 'photoUrl');

  console.log(
    `\n✅ Готово. Загружено файлов: ${uploaded}, обновлено ссылок: ${updated}, пропущено (нет файла): ${missing}`,
  );
  await mongoose.disconnect();
  process.exit(0);
}

main().catch((err) => {
  console.error('❌ Ошибка миграции:', err);
  process.exit(1);
});
