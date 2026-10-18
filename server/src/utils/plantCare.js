export const DAY_MS = 86400000;
export const CHECKUP_DAYS = 7;
export const GROWTH_STAGES = ['seed', 'sprout', 'seedling', 'growing', 'mature', 'flowering'];
export const CARE_FIELDS = ['wateringIntervalDays', 'waterAmountMl', 'fertilizerIntervalDays', 'light', 'temperature'];

export function changedCareFields(current = {}, updates = {}) {
  return CARE_FIELDS.filter((field) => updates[field] !== undefined && updates[field] !== current[field]);
}

export function asDate(value) {
  if (value === null || value === undefined || value === '') return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

export function careDueAt(base, intervalDays, snoozedUntil, fallback = new Date()) {
  const date = asDate(base) || asDate(fallback) || new Date();
  const interval = Number(intervalDays);
  const due = new Date(date.getTime() + (Number.isFinite(interval) && interval > 0 ? interval : 7) * DAY_MS);
  const snooze = asDate(snoozedUntil);
  return snooze && snooze > due ? snooze : due;
}

export function weeklyCheckupDueAt(plant, now = new Date()) {
  const weeklyDue = careDueAt(plant.lastCheckupAt || plant.createdAt, CHECKUP_DAYS, null, now);
  const explicitDue = asDate(plant.nextCheckupAt);
  // Old 14/30-day model schedules are brought back to the requested weekly cadence.
  return explicitDue && explicitDue < weeklyDue ? explicitDue : weeklyDue;
}

export function healthStatusFor(result) {
  if (result.isHealthy === true) return 'thriving';
  return Number(result.healthScore) >= 50 ? 'needs_attention' : 'sick';
}

export function healthTrend(previousScore, currentScore) {
  if (typeof previousScore !== 'number' || !Number.isFinite(previousScore)) return null;
  return currentScore > previousScore + 2 ? 'up' : currentScore < previousScore - 2 ? 'down' : 'same';
}

export function diagnosisSnapshot(result, now = new Date(), scanId) {
  return {
    isHealthy: result.isHealthy === true,
    title: result.diagnosis?.title || '',
    description: result.diagnosis?.description || '',
    confidence: Number(result.diagnosis?.confidence) || 0,
    treatmentPlan: Array.isArray(result.treatmentPlan) ? result.treatmentPlan : [],
    ...(scanId ? { scanId } : {}),
    scannedAt: now,
  };
}

export function journalSnapshot(result, previousScore = null) {
  return {
    healthScore: result.healthScore,
    healthStatus: healthStatusFor(result),
    diagnosisTitle: result.diagnosis?.title || '',
    diagnosisDescription: result.diagnosis?.description || '',
    analysis: result.progressNote || result.diagnosis?.description || '',
    trend: healthTrend(previousScore, result.healthScore),
  };
}

export function applyPlantAnalysis(plant, result, { photoUrl, now = new Date(), scanId } = {}) {
  if (result?.isPlant !== true) return false;
  plant.previousHealthScore = plant.lastDiagnosis ? plant.healthScore : null;
  plant.healthTrend = healthTrend(plant.previousHealthScore, result.healthScore);
  plant.lastProgressNote = result.progressNote || '';
  plant.healthScore = result.healthScore;
  plant.healthStatus = healthStatusFor(result);
  plant.lastDiagnosis = diagnosisSnapshot(result, now, scanId);
  if (result.species) plant.species = result.species;
  if (GROWTH_STAGES.includes(result.growthStage)) plant.stage = result.growthStage;
  plant.care ||= {};
  const manualFields = new Set(plant.careManualFields || []);
  const care = result.careAdvice || {};
  for (const field of ['wateringIntervalDays', 'waterAmountMl', 'fertilizerIntervalDays']) {
    if (!manualFields.has(field) && Number.isFinite(Number(care[field])) && Number(care[field]) > 0) plant.care[field] = Number(care[field]);
  }
  for (const field of ['light', 'temperature']) {
    if (!manualFields.has(field) && typeof care[field] === 'string' && care[field].trim()) plant.care[field] = care[field].trim();
  }
  plant.care.checkupIntervalDays = CHECKUP_DAYS;
  if (photoUrl) plant.photoUrl = photoUrl;
  plant.lastCheckupAt = now;
  plant.nextCheckupAt = new Date(now.getTime() + CHECKUP_DAYS * DAY_MS);
  plant.lastCheckupNotifiedAt = null;
  plant.lastCheckupDeliveredAt = null;
  return true;
}

export function validateCare(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Некорректный формат ухода');
  const care = {};
  const ranges = { wateringIntervalDays: [1, 365], fertilizerIntervalDays: [1, 365], waterAmountMl: [1, 100000] };
  for (const [key, [min, max]] of Object.entries(ranges)) {
    if (input[key] === undefined) continue;
    const value = Number(input[key]);
    if (!Number.isInteger(value) || value < min || value > max) throw new Error(`Некорректное значение ${key}`);
    care[key] = value;
  }
  for (const key of ['light', 'temperature']) {
    if (input[key] !== undefined) care[key] = String(input[key]).trim().slice(0, 500);
  }
  // Weekly photos are a product cadence, not a model recommendation.
  care.checkupIntervalDays = CHECKUP_DAYS;
  return care;
}

/** Anchor weeks to the plant's first day rather than to UTC calendar Mondays. */
export function buildWeeklyHistory(plant, entries, now = new Date()) {
  const start = asDate(plant.createdAt) || asDate(now) || new Date();
  const today = asDate(now) || new Date();
  const weekMs = CHECKUP_DAYS * DAY_MS;
  const count = Math.max(1, Math.floor((today.getTime() - start.getTime()) / weekMs) + 1);
  const buckets = Array.from({ length: count }, (_, index) => ({
    weekNumber: index + 1,
    weekStart: new Date(start.getTime() + index * weekMs),
    weekEnd: new Date(start.getTime() + (index + 1) * weekMs),
    status: index === count - 1 ? 'upcoming' : 'missed',
    entries: [],
  }));
  for (const entry of entries) {
    if (!entry.photoUrl) continue;
    const captured = asDate(entry.createdAt);
    if (!captured || captured > today) continue;
    const index = Math.max(0, Math.floor((captured.getTime() - start.getTime()) / weekMs));
    if (index >= buckets.length) continue;
    buckets[index].entries.push(entry);
    buckets[index].status = 'recorded';
  }
  for (const bucket of buckets) bucket.entries.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
  return buckets;
}
