import { CHECKUP_DAYS } from './plantCare.js';

const BANDS = { none: [85, 100], mild: [70, 84], moderate: [50, 69], severe: [30, 49], critical: [0, 29] };

export function reconcileHealth(result) {
  if (!result || typeof result !== 'object' || typeof result.isPlant !== 'boolean') {
    throw new Error('ИИ вернул некорректный анализ');
  }
  if (!result.isPlant) return { ...result, nextCheckupDays: CHECKUP_DAYS };
  if (result.healthScore === null || result.healthScore === '') throw new Error('ИИ не вернул оценку здоровья');
  let score = Number(result.healthScore);
  if (!Number.isFinite(score)) throw new Error('ИИ не вернул оценку здоровья');
  score = Math.max(0, Math.min(100, Math.round(score)));
  let severity = String(result.severity || '').toLowerCase();
  if (!BANDS[severity]) {
    severity = score >= 85 ? 'none' : score >= 70 ? 'mild' : score >= 50 ? 'moderate' : score >= 30 ? 'severe' : 'critical';
  }
  // A false healthy flag is evidence of a current issue, even when severity is inconsistent.
  if (severity === 'none' && result.isHealthy === false) severity = 'mild';
  const [minimum, maximum] = BANDS[severity];
  score = Math.max(minimum, Math.min(maximum, score));
  const isHealthy = severity === 'none';
  const diagnosis = {
    title: String(result.diagnosis?.title || (isHealthy ? 'Здоровое растение' : 'Нужен уход')),
    description: String(result.diagnosis?.description || ''),
    confidence: Math.max(0, Math.min(1, Number(result.diagnosis?.confidence) || 0)),
  };
  const advice = result.careAdvice || {};
  const boundedInteger = (value, fallback, max) => Number.isFinite(Number(value)) && Number(value) > 0
    ? Math.max(1, Math.min(max, Math.round(Number(value)))) : fallback;
  return {
    ...result,
    diagnosis,
    healthScore: score,
    severity,
    isHealthy,
    // Current health and improvement are independent; recovered plants lose old treatment tasks.
    treatmentPlan: isHealthy ? [] : (Array.isArray(result.treatmentPlan) ? result.treatmentPlan.map(String) : []),
    growthAdvice: Array.isArray(result.growthAdvice) ? result.growthAdvice.map(String) : [],
    progressNote: typeof result.progressNote === 'string' ? result.progressNote : '',
    nextCheckupDays: CHECKUP_DAYS,
    careAdvice: {
      ...advice,
      wateringIntervalDays: boundedInteger(advice.wateringIntervalDays, 7, 365),
      fertilizerIntervalDays: boundedInteger(advice.fertilizerIntervalDays, 30, 365),
      waterAmountMl: boundedInteger(advice.waterAmountMl, 250, 100000),
    },
  };
}
