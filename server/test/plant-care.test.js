import test from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { Plant } from '../src/models/Plant.js';
import { JournalEntry } from '../src/models/JournalEntry.js';
import { plantView, baselineData, analysisOptions } from '../src/services/plantProgress.js';
import { applyPlantAnalysis, buildWeeklyHistory, careDueAt, DAY_MS, journalSnapshot, validateCare, weeklyCheckupDueAt } from '../src/utils/plantCare.js';
import { reconcileHealth } from '../src/utils/healthAnalysis.js';

const origin = new Date('2026-10-01T09:15:00Z');
const day = (days) => new Date(origin.getTime() + days * DAY_MS);
const analysis = (overrides = {}) => reconcileHealth({
  isPlant: true, isHealthy: false, severity: 'moderate', healthScore: 60,
  diagnosis: { title: 'Стресс после пересадки', description: 'Часть листьев поникла', confidence: .9 },
  treatmentPlan: ['Проверить дренаж'], careAdvice: {}, ...overrides,
});
const createPlant = (extras = {}) => new Plant({ userId: new mongoose.Types.ObjectId(), name: 'Бамбук у окна', createdAt: origin, ...extras });

test('improved score keeps current symptoms visible, then real recovery clears previous treatment', () => {
  const plant = createPlant({ healthScore: 40, healthStatus: 'sick', lastDiagnosis: { isHealthy: false, title: 'Стресс', treatmentPlan: ['Старое действие'] } });
  const better = analysis({ healthScore: 65, progressNote: 'Листья выпрямились, но повреждения остались' });
  applyPlantAnalysis(plant, better, { photoUrl: '/uploads/week2.jpg', now: day(7) });
  assert.equal(plant.healthTrend, 'up');
  assert.equal(plant.previousHealthScore, 40);
  assert.equal(plant.healthStatus, 'needs_attention');
  assert.equal(plant.lastDiagnosis.isHealthy, false);
  assert.equal(plant.lastProgressNote, better.progressNote);
  const recovered = analysis({ severity: 'none', isHealthy: true, healthScore: 95, diagnosis: { title: 'Здоровое растение' }, treatmentPlan: ['Устаревший план'] });
  applyPlantAnalysis(plant, recovered, { photoUrl: '/uploads/week3.jpg', now: day(14) });
  assert.equal(plant.healthStatus, 'thriving');
  assert.equal(plant.lastDiagnosis.isHealthy, true);
  assert.deepEqual([...plant.lastDiagnosis.treatmentPlan], []);
  assert.equal(plant.lastDiagnosis.title, 'Здоровое растение');
  assert.equal(plant.photoUrl, '/uploads/week3.jpg');
});

test('healthy flag cannot conceal moderate severity, and unhealthy flag cannot leave severity none', () => {
  const moderate = analysis({ isHealthy: true, healthScore: 97 });
  assert.equal(moderate.isHealthy, false);
  assert.equal(moderate.healthScore, 69);
  const inconsistent = analysis({ isHealthy: false, severity: 'none', healthScore: 96 });
  assert.equal(inconsistent.severity, 'mild');
  assert.equal(inconsistent.healthScore, 84);
});

test('invalid AI responses fail instead of inventing a healthy score', () => {
  assert.throws(() => reconcileHealth({ healthScore: 90 }), /некорректный анализ/);
  assert.throws(() => analysis({ healthScore: undefined }), /оценку здоровья/);
  assert.equal(analysis({ severity: 'critical', healthScore: 0 }).healthScore, 0);
});

test('nonplant analysis cannot change any plant health, history date, or schedule', () => {
  const plant = createPlant({ photoUrl: '/uploads/old.jpg', lastCheckupAt: origin, nextCheckupAt: day(7), healthScore: 60 });
  const before = plant.toObject();
  assert.equal(applyPlantAnalysis(plant, { isPlant: false }, { photoUrl: '/uploads/table.jpg', now: day(8) }), false);
  assert.deepEqual(plant.toObject(), before);
});

test('all accepted photos schedule seven days and distinguish stable/down trends', () => {
  const plant = createPlant({ healthScore: 60, lastDiagnosis: { title: 'Прошлый диагноз' }, lastCheckupNotifiedAt: day(4) });
  applyPlantAnalysis(plant, analysis({ nextCheckupDays: 30, healthScore: 61 }), { now: day(7) });
  assert.equal(plant.healthTrend, 'same');
  assert.equal(plant.nextCheckupAt.getTime(), day(14).getTime());
  assert.equal(plant.care.checkupIntervalDays, 7);
  assert.equal(plant.lastCheckupNotifiedAt, null);
  applyPlantAnalysis(plant, analysis({ severity: 'severe', healthScore: 45 }), { now: day(14) });
  assert.equal(plant.healthTrend, 'down');
  assert.equal(plant.healthStatus, 'sick');
});

test('legacy long checkup interval migrates in due calculations; early due remains early', () => {
  assert.equal(weeklyCheckupDueAt({ createdAt: origin, nextCheckupAt: day(30) }).getTime(), day(7).getTime());
  assert.equal(weeklyCheckupDueAt({ createdAt: origin, nextCheckupAt: day(3) }).getTime(), day(3).getTime());
  assert.equal(weeklyCheckupDueAt({ createdAt: origin, lastCheckupAt: day(8), nextCheckupAt: day(40) }).getTime(), day(15).getTime());
});

test('snooze postpones care without pretending it was done or advancing an already future due', () => {
  assert.equal(careDueAt(origin, 7, day(10)).getTime(), day(10).getTime());
  assert.equal(careDueAt(origin, 30, day(10)).getTime(), day(30).getTime());
  const plant = createPlant({ lastFertilizedAt: origin, fertilizingSnoozedUntil: day(33) });
  assert.equal(plant.fertilizingDueAt().getTime(), day(33).getTime());
  assert.equal(plant.lastFertilizedAt.getTime(), origin.getTime());
  plant.lastFertilizedAt = day(33);
  plant.fertilizingSnoozedUntil = null;
  assert.equal(plant.fertilizingDueAt().getTime(), day(63).getTime());
});

test('care input rejects invalid intervals, allows text updates, and fixes weekly cadence', () => {
  for (const value of [0, -1, 'bad', 1.5, 366, Infinity]) assert.throws(() => validateCare({ wateringIntervalDays: value }));
  assert.deepEqual(validateCare({ fertilizerIntervalDays: '21', light: ' Окно ', checkupIntervalDays: 30 }), { fertilizerIntervalDays: 21, light: 'Окно', checkupIntervalDays: 7 });
  assert.throws(() => validateCare([]));
});

test('manual care preferences survive persistence and repeated AI checks, while other advice can update', () => {
  const original = createPlant({
    care: { wateringIntervalDays: 10, fertilizerIntervalDays: 21, light: 'Восточное окно' },
    careManualFields: ['wateringIntervalDays', 'fertilizerIntervalDays', 'light'],
  });
  const restored = Plant.hydrate(original.toObject());
  const result = analysis({ careAdvice: { wateringIntervalDays: 2, fertilizerIntervalDays: 7, light: 'Тень', waterAmountMl: 500, temperature: '20-25°C' } });
  applyPlantAnalysis(restored, result, { now: day(7) });
  const restoredAgain = Plant.hydrate(restored.toObject());
  applyPlantAnalysis(restoredAgain, analysis({ careAdvice: { wateringIntervalDays: 3, fertilizerIntervalDays: 8, light: 'Яркий свет', waterAmountMl: 600 } }), { now: day(14) });
  assert.equal(restoredAgain.care.wateringIntervalDays, 10);
  assert.equal(restoredAgain.care.fertilizerIntervalDays, 21);
  assert.equal(restoredAgain.care.light, 'Восточное окно');
  assert.equal(restoredAgain.care.waterAmountMl, 600);
  assert.equal(restoredAgain.care.temperature, '20-25°C');
  assert.equal(restoredAgain.care.checkupIntervalDays, 7);
  assert.deepEqual([...restoredAgain.careManualFields], ['wateringIntervalDays', 'fertilizerIntervalDays', 'light']);
  assert.equal(restoredAgain.validateSync(), undefined);
});

test('weekly timeline includes all photos, a missed week, current upcoming week, and excludes note-only/future entries', () => {
  const plant = { createdAt: origin };
  const entries = [
    { _id: 'week1', photoUrl: '/uploads/1.jpg', createdAt: day(0) },
    { _id: 'week3b', photoUrl: '/uploads/3b.jpg', createdAt: day(16) },
    { _id: 'week3a', photoUrl: '/uploads/3a.jpg', createdAt: day(14) },
    { _id: 'note', note: 'Полил', createdAt: day(8) },
    { _id: 'future', photoUrl: '/uploads/future.jpg', createdAt: day(40) },
  ];
  const weeks = buildWeeklyHistory(plant, entries, day(22));
  assert.deepEqual(weeks.map((week) => [week.weekNumber, week.status]), [[1, 'recorded'], [2, 'missed'], [3, 'recorded'], [4, 'upcoming']]);
  assert.deepEqual(weeks[2].entries.map((e) => e._id), ['week3a', 'week3b']);
  assert.equal(weeks[3].weekStart.getTime(), day(21).getTime());
  assert.equal(weeks[3].weekEnd.getTime(), day(28).getTime());
});

test('week boundary belongs to the new week; new and future-created plants always have one week', () => {
  const weeks = buildWeeklyHistory({ createdAt: origin }, [{ photoUrl: 'x', createdAt: day(7) }], day(7));
  assert.deepEqual(weeks.map((w) => w.status), ['missed', 'recorded']);
  assert.equal(buildWeeklyHistory({ createdAt: origin }, [], origin).length, 1);
  assert.equal(buildWeeklyHistory({ createdAt: day(10) }, [], origin).length, 1);
});

test('snapshots retain diagnosis and source independently from subsequent plant health updates', () => {
  const result = analysis({ healthScore: 65 });
  const entry = new JournalEntry({ userId: new mongoose.Types.ObjectId(), plantId: new mongoose.Types.ObjectId(), source: 'checkup', ...journalSnapshot(result, 40) });
  assert.equal(entry.trend, 'up');
  assert.equal(entry.healthStatus, 'needs_attention');
  assert.equal(entry.diagnosisTitle, 'Стресс после пересадки');
  assert.equal(entry.validateSync(), undefined);
  const baseline = baselineData(createPlant({ lastCheckupAt: day(7), lastDiagnosis: { title: 'Здоровое' } }));
  assert.equal(baseline.createdAt.getTime(), day(7).getTime());
  assert.equal(baseline.source, 'baseline');
});

test('plant view exposes disabled reminders, care due, weekly cadence, and identity unchanged', () => {
  const plant = createPlant({ name: 'Бамбук — спальня', care: { checkupIntervalDays: 30 } });
  const view = plantView(plant, [{ plantId: plant._id, type: 'fertilizing', active: false }], day(31));
  assert.deepEqual(view.reminderEnabled, { watering: true, fertilizing: false, checkup: true });
  assert.equal(view.needsFertilizer, true);
  assert.equal(view.care.checkupIntervalDays, 7);
  assert.equal(view.name, 'Бамбук — спальня');
  const options = analysisOptions(plant);
  assert.equal(options.plantContext.name, plant.name);
  assert.equal(options.previousHealthScore, null);
});
