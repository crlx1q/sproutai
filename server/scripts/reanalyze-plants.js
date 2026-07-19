// Разовый скрипт пересчёта состояния растений.
// Берёт УЖЕ сохранённые фото (Cloudinary или локальный диск) и заново
// прогоняет их через ИИ с новой честной шкалой оценки, после чего обновляет
// в базе healthScore / диагноз / статус / расписание следующего чекапа.
// НИЧЕГО НЕ УДАЛЯЕТ — только перезаписывает значения. Это альтернатива
// полной очистке базы: старые записи и фото остаются, меняются лишь оценки.
//
// Использование:
//   cd server
//   node scripts/reanalyze-plants.js you@example.com        // один пользователь
//   node scripts/reanalyze-plants.js --all                  // все растения
//   node scripts/reanalyze-plants.js you@example.com --dry  // прогон без записи
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import mongoose from 'mongoose';
import { config } from '../src/config.js';
import { User } from '../src/models/User.js';
import { Plant } from '../src/models/Plant.js';
import { Scan } from '../src/models/Scan.js';
import { analyzePlantImage } from '../src/services/gemini.js';
import { toGeminiJpeg, uploadsDir } from '../src/utils/upload.js';

const args = process.argv.slice(2);
const DRY = args.includes('--dry');
const ALL = args.includes('--all');
const email = args.find((a) => !a.startsWith('--'));

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Достаём байты картинки: из Cloudinary/https или с локального диска.
async function loadImageBuffer(url) {
  if (!url) return null;
  if (/^https?:\/\//i.test(url)) {
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(`HTTP ${resp.status} при загрузке фото`);
    return Buffer.from(await resp.arrayBuffer());
  }
  if (url.startsWith('/uploads/')) {
    return fs.promises.readFile(path.join(uploadsDir, path.basename(url)));
  }
  return null;
}

// Ищем лучшее доступное фото: photoUrl растения, иначе последний скан.
async function resolvePhotoUrl(plant) {
  if (plant.photoUrl) return plant.photoUrl;
  const lastScan = await Scan.findOne({ plantId: plant._id }).sort({ createdAt: -1 });
  return lastScan?.imageUrl || null;
}

async function main() {
  if (!email && !ALL) {
    console.error('Использование: node scripts/reanalyze-plants.js <email> | --all [--dry]');
    process.exit(1);
  }

  await mongoose.connect(config.mongoUri);

  let filter = {};
  if (!ALL) {
    const user = await User.findOne({ email: new RegExp(`^${escapeRegex(email)}$`, 'i') });
    if (!user) {
      console.error('Пользователь не найден:', email);
      await mongoose.disconnect();
      process.exit(1);
    }
    filter = { userId: user._id };
    console.log(`Пересчитываем растения пользователя ${email}`);
  } else {
    console.log('Пересчитываем растения ВСЕХ пользователей');
  }
  if (DRY) console.log('(режим --dry: изменения НЕ сохраняются)');
  console.log('');

  const plants = await Plant.find(filter);
  console.log(`Найдено растений: ${plants.length}\n`);

  let ok = 0;
  let skipped = 0;
  let failed = 0;

  for (const plant of plants) {
    const label = `${plant.name}${plant.species ? ` (${plant.species})` : ''}`;
    try {
      const photoUrl = await resolvePhotoUrl(plant);
      const buffer = await loadImageBuffer(photoUrl);
      if (!buffer) {
        console.log(`⏭  ${label} — нет доступного фото, пропуск`);
        skipped++;
        continue;
      }

      const geminiJpeg = await toGeminiJpeg(buffer);
      const result = await analyzePlantImage(geminiJpeg, {
        previousDiagnosis: plant.lastDiagnosis || null,
        plantContext: {
          name: plant.name,
          species: plant.species,
          location: plant.location,
          stage: plant.stage,
        },
        mode: plant.origin === 'grown' ? 'grow' : 'diagnose',
      });

      if (!result.isPlant) {
        console.log(`⏭  ${label} — ИИ не распознал растение на фото, пропуск`);
        skipped++;
        continue;
      }

      const oldScore = plant.healthScore;
      const nextDays =
        result.nextCheckupDays || plant.care.checkupIntervalDays || 14;

      if (!DRY) {
        plant.lastDiagnosis = {
          isHealthy: result.isHealthy,
          title: result.diagnosis.title,
          description: result.diagnosis.description,
          confidence: result.diagnosis.confidence,
          treatmentPlan: result.treatmentPlan,
          scanId: plant.lastDiagnosis?.scanId || null,
          scannedAt: new Date(),
        };
        plant.healthScore = result.healthScore;
        plant.healthStatus = result.isHealthy
          ? 'thriving'
          : result.healthScore >= 55
            ? 'needs_attention'
            : 'sick';
        if (result.species) plant.species = result.species;
        plant.care.checkupIntervalDays = nextDays;
        plant.lastCheckupAt = new Date();
        plant.nextCheckupAt = new Date(Date.now() + nextDays * 86400000);
        await plant.save();
      }

      console.log(
        `✅ ${label}: ${oldScore ?? '—'} → ${result.healthScore}/100 · ${result.diagnosis.title}`,
      );
      ok++;
      await sleep(1200); // бережём лимиты Gemini
    } catch (e) {
      console.log(`❌ ${label} — ошибка: ${e.message}`);
      failed++;
    }
  }

  console.log(`\nИтого: обновлено ${ok}, пропущено ${skipped}, ошибок ${failed}`);
  await mongoose.disconnect();
  console.log('Готово ✅');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
