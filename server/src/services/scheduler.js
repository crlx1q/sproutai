import { Plant } from '../models/Plant.js';
import { Reminder } from '../models/Reminder.js';
import { sendToUser, isPushEnabled } from './push.js';

const CHECK_INTERVAL_MS = 15 * 60 * 1000;
const LEASE_MS = 10 * 60 * 1000;
const status = { running: false, lastRunAt: null, lastCompletedAt: null, lastErrorCode: null };
let timer = null;
let stopped = true;

const kinds = [
  { type: 'watering', due: 'wateringDueAt', sent: 'lastWaterDeliveredAt', legacySent: 'lastWaterNotifiedAt', lock: 'waterNotificationLockUntil', cycle: ['lastWateredAt', 'wateringSnoozedUntil', 'care.wateringIntervalDays'] },
  { type: 'fertilizing', due: 'fertilizingDueAt', sent: 'lastFertilizeDeliveredAt', legacySent: 'lastFertilizeNotifiedAt', lock: 'fertilizeNotificationLockUntil', cycle: ['lastFertilizedAt', 'fertilizingSnoozedUntil', 'care.fertilizerIntervalDays'] },
  { type: 'checkup', due: 'checkupDueAt', sent: 'lastCheckupDeliveredAt', legacySent: 'lastCheckupNotifiedAt', lock: 'checkupNotificationLockUntil', cycle: ['lastCheckupAt', 'nextCheckupAt'] },
];

function cycleFilter(plant, kind) {
  return Object.fromEntries(kind.cycle.map((key) => [key, key.split('.').reduce((value, part) => value?.[part], plant) ?? null]));
}

async function acquire(plant, kind, due, now) {
  const lockUntil = new Date(now.getTime() + LEASE_MS);
  const result = await Plant.updateOne({
    _id: plant._id,
    ...cycleFilter(plant, kind),
    $and: [
      { $or: [{ [kind.sent]: null }, { [kind.sent]: { $lt: due } }] },
      { $or: [{ [kind.lock]: null }, { [kind.lock]: { $lte: now } }] },
    ],
  }, { $set: { [kind.lock]: lockUntil } });
  return result.modifiedCount === 1 ? lockUntil : null;
}

async function complete(plant, kind, lockUntil, sentAt) {
  await Plant.updateOne({ _id: plant._id, [kind.lock]: lockUntil }, {
    ...(sentAt ? { $set: { [kind.sent]: sentAt, [kind.legacySent]: sentAt } } : {}),
    $unset: { [kind.lock]: '' },
  });
}

/** Injectable runner permits offline tests without a database or actual pushes. */
export function createReminderRunner({
  enabled = isPushEnabled,
  plants = () => Plant.find({}).cursor(),
  disabledReminders = () => Reminder.find({ active: false }).select('plantId type').lean(),
  claim = acquire,
  finish = complete,
  send = sendToUser,
  clock = () => new Date(),
  onError = (error) => console.error('[scheduler]', error?.code || error?.name || 'reminder_failed'),
} = {}) {
  let running = false;
  return async function run() {
    if (running || !enabled()) return;
    running = true;
    status.running = true;
    status.lastRunAt = clock().toISOString();
    status.lastErrorCode = null;
    try {
      const inactive = new Set((await disabledReminders()).map((reminder) => `${reminder.plantId}:${reminder.type}`));
      for await (const plant of plants()) {
        for (const kind of kinds) {
          let lease;
          try {
            const due = plant[kind.due]();
            const now = clock();
            if (!(due instanceof Date) || !Number.isFinite(due.getTime()) || due > now || inactive.has(`${plant._id}:${kind.type}`) || (plant[kind.sent] && plant[kind.sent] >= due)) continue;
            lease = await claim(plant, kind, due, now);
            if (!lease) continue;
            const name = plant.name;
            const content = kind.type === 'watering'
              ? { title: `Пора полить: ${name} 💧`, body: `Проверьте грунт. Если он подсох, полейте ${name} и отметьте полив в Sprout AI.` }
              : kind.type === 'fertilizing'
                ? { title: `Пора подкормить: ${name} 🌱`, body: 'Проверьте рекомендации по подкормке. Можно отметить удобрение или отложить напоминание.' }
                : { title: `Еженедельное фото: ${name} 📸`, body: 'Сделайте свежее фото: ИИ сравнит состояние, а снимок сохранится в истории роста.' };
            const delivery = await send(plant.userId, { ...content, data: { type: kind.type, plantId: String(plant._id), dueAt: due.toISOString() } });
            if (delivery.failed > 0) status.lastErrorCode = Object.keys(delivery.errors || {})[0] || 'push_delivery_failed';
            // An absent token or rejected delivery must remain retryable.
            await finish(plant, kind, lease, delivery.sent > 0 ? clock() : null);
            lease = null;
          } catch (error) {
            status.lastErrorCode = error?.code || error?.name || 'reminder_failed';
            onError(error);
          } finally {
            if (lease) {
              try { await finish(plant, kind, lease, null); } catch (error) { onError(error); }
            }
          }
        }
      }
      status.lastCompletedAt = clock().toISOString();
    } catch (error) {
      status.lastErrorCode = error?.code || error?.name || 'reminder_failed';
      onError(error);
    } finally {
      running = false;
      status.running = false;
    }
  };
}

export const runOnce = createReminderRunner();

export function getReminderSchedulerStatus() {
  return { started: !stopped, intervalMinutes: CHECK_INTERVAL_MS / 60000, ...status };
}

export function stopReminderScheduler() {
  stopped = true;
  clearTimeout(timer);
  timer = null;
}

/** Self-rescheduling prevents overlaps; persisted leases cover multiple dynos. */
export function startReminderScheduler() {
  if (!stopped) return stopReminderScheduler;
  stopped = false;
  async function tick() {
    if (stopped) return;
    await runOnce();
    if (!stopped) {
      timer = setTimeout(tick, CHECK_INTERVAL_MS);
      timer.unref?.();
    }
  }
  // Catch up promptly after a restart or a sleeping host.
  timer = setTimeout(tick, 1000);
  timer.unref?.();
  console.log('[scheduler] Reminder scheduler started (15 minute interval).');
  return stopReminderScheduler;
}
