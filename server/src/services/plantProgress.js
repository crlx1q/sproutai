import { JournalEntry } from '../models/JournalEntry.js';
import { Reminder } from '../models/Reminder.js';
import { CHECKUP_DAYS } from '../utils/plantCare.js';

export function plantView(plant, reminders = [], now = new Date()) {
  const obj = plant.toObject({ virtuals: false });
  obj.care = { ...obj.care, checkupIntervalDays: CHECKUP_DAYS };
  obj.wateringDueAt = plant.wateringDueAt();
  obj.needsWater = obj.wateringDueAt <= now;
  obj.fertilizingDueAt = plant.fertilizingDueAt();
  obj.needsFertilizer = obj.fertilizingDueAt <= now;
  obj.checkupDueAt = plant.checkupDueAt();
  obj.nextCheckupAt = obj.checkupDueAt;
  obj.needsCheckup = obj.checkupDueAt <= now;
  obj.reminderEnabled = Object.fromEntries(['watering', 'fertilizing', 'checkup'].map((type) => [
    type, !reminders.some((r) => String(r.plantId) === String(plant._id) && r.type === type && r.active === false),
  ]));
  return obj;
}

export async function ownPlantView(plant) {
  return plantView(plant, await Reminder.find({ plantId: plant._id }));
}

export async function syncCareReminders(plant) {
  for (const [type, intervalDays, nextDueAt] of [
    ['watering', plant.care.wateringIntervalDays, plant.wateringDueAt()],
    ['fertilizing', plant.care.fertilizerIntervalDays, plant.fertilizingDueAt()],
    ['checkup', CHECKUP_DAYS, plant.checkupDueAt()],
  ]) {
    await Reminder.updateOne({ plantId: plant._id, type }, {
      $set: { intervalDays, nextDueAt },
      $setOnInsert: { userId: plant.userId, plantId: plant._id, type, active: true },
    }, { upsert: true });
  }
}

export function analysisOptions(plant) {
  return {
    previousDiagnosis: plant.lastDiagnosis || null,
    previousHealthScore: plant.lastDiagnosis ? plant.healthScore : null,
    previousPhotoUrl: plant.photoUrl,
    careEvents: { lastWateredAt: plant.lastWateredAt, lastFertilizedAt: plant.lastFertilizedAt },
    plantContext: { name: plant.name, species: plant.species, location: plant.location, stage: plant.stage, plantedAt: plant.plantedAt },
    mode: plant.origin === 'grown' ? 'grow' : 'checkup',
  };
}

export function baselineData(plant) {
  // Older journal uploads changed health without changing the cover image. Do not
  // attribute that later diagnosis to the old cover when its photo/date is unknown.
  const diagnosisMatchesPhoto = Boolean(plant.lastDiagnosis && (plant.lastCheckupAt ||
    Math.abs(new Date(plant.lastDiagnosis.scannedAt || plant.createdAt) - new Date(plant.createdAt)) < 60000));
  return {
    userId: plant.userId, plantId: plant._id, photoUrl: plant.photoUrl,
    kind: 'before', source: 'baseline', note: 'Первое фото в истории растения',
    healthScore: diagnosisMatchesPhoto ? plant.healthScore : null,
    healthStatus: diagnosisMatchesPhoto ? plant.healthStatus : null,
    diagnosisTitle: diagnosisMatchesPhoto ? plant.lastDiagnosis?.title || '' : '',
    diagnosisDescription: diagnosisMatchesPhoto ? plant.lastDiagnosis?.description || '' : '',
    analysis: diagnosisMatchesPhoto ? plant.lastDiagnosis?.description || '' : '',
    createdAt: plant.lastCheckupAt || plant.createdAt,
  };
}

export async function ensureBaseline(plant) {
  if (!plant.photoUrl) return;
  const exists = await JournalEntry.exists({ plantId: plant._id, $or: [{ source: 'baseline' }, { photoUrl: plant.photoUrl }] });
  if (!exists) await JournalEntry.create(baselineData(plant));
}

