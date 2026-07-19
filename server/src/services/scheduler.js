import { Plant } from '../models/Plant.js';
import { sendToUser, isPushEnabled } from './push.js';

const CHECK_INTERVAL_MS = 15 * 60 * 1000; // проверка каждые 15 минут

/**
 * Один проход: находим растения, которым пора полив/удобрение/
 * контрольное фото, и шлём пуш владельцу. Каждый цикл ухода
 * уведомляем только один раз (сравниваем время «пора» с временем
 * последнего уведомления).
 */
async function runOnce() {
  if (!isPushEnabled()) return;
  const now = new Date();
  const plants = await Plant.find({});
  for (const plant of plants) {
    try {
      const waterDue = plant.wateringDueAt();
      if (
        waterDue <= now &&
        (!plant.lastWaterNotifiedAt || plant.lastWaterNotifiedAt < waterDue)
      ) {
        await sendToUser(plant.userId, {
          title: `Пора полить: ${plant.name} 💧`,
          body: `${plant.name} ждёт около ${plant.care.waterAmountMl} мл воды. Отметьте полив в Sprout AI.`,
          data: { type: 'watering', plantId: String(plant._id) },
        });
        plant.lastWaterNotifiedAt = now;
        await plant.save();
      }

      const fertDue = plant.fertilizingDueAt();
      if (
        fertDue <= now &&
        (!plant.lastFertilizeNotifiedAt || plant.lastFertilizeNotifiedAt < fertDue)
      ) {
        await sendToUser(plant.userId, {
          title: `Пора удобрить: ${plant.name} 🌱`,
          body: `${plant.name} пора подкормить. Загляните в Sprout AI.`,
          data: { type: 'fertilizing', plantId: String(plant._id) },
        });
        plant.lastFertilizeNotifiedAt = now;
        await plant.save();
      }

      // Контрольное фото: ПОРА перефотографировать растение, чтобы ИИ обновил состояние.
      const checkupDue = plant.checkupDueAt();
      if (
        checkupDue <= now &&
        (!plant.lastCheckupNotifiedAt || plant.lastCheckupNotifiedAt < checkupDue)
      ) {
        await sendToUser(plant.userId, {
          title: `Пора обновить фото: ${plant.name} 📸`,
          body: `ИИ проверит, как ${plant.name} изменилось. Сделайте свежее фото в Sprout AI.`,
          data: { type: 'checkup', plantId: String(plant._id) },
        });
        plant.lastCheckupNotifiedAt = now;
        await plant.save();
      }
    } catch (err) {
      console.error('[scheduler] plant', String(plant._id), err.message);
    }
  }
}

/** Запускает периодическую проверку напоминаний. */
export function startReminderScheduler() {
  setTimeout(() => {
    runOnce().catch((e) => console.error('[scheduler]', e.message));
    setInterval(() => {
      runOnce().catch((e) => console.error('[scheduler]', e.message));
    }, CHECK_INTERVAL_MS);
  }, 60 * 1000);
  console.log('[scheduler] reminder scheduler started');
}

export { runOnce };
