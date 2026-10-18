import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import mongoose from 'mongoose';
import sharp from 'sharp';
import plantRoutes from '../src/routes/plants.js';
import { Plant } from '../src/models/Plant.js';
import { JournalEntry } from '../src/models/JournalEntry.js';
import { Reminder } from '../src/models/Reminder.js';
import { Scan } from '../src/models/Scan.js';
import { scanQuota, AnalysisError } from '../src/services/scanQuota.js';
import { applyPlantAnalysis } from '../src/utils/plantCare.js';

const userId = new mongoose.Types.ObjectId();
const plantId = new mongoose.Types.ObjectId();
let server;
let baseUrl;
before(async () => {
  // Replace authentication only; execute the real Express routes and input/response logic.
  plantRoutes.stack[0].handle = (req, res, next) => { req.user = { _id: userId }; next(); };
  const app = express();
  app.use(express.json());
  app.use('/api/plants', plantRoutes);
  app.use((error, req, res, next) => res.status(500).json({ error: error.message }));
  server = await new Promise((resolve) => { const listening = app.listen(0, '127.0.0.1', () => resolve(listening)); });
  baseUrl = `http://127.0.0.1:${server.address().port}/api/plants`;
});
after(() => new Promise((resolve) => server.close(resolve)));

async function request(path, method = 'GET', body) {
  const response = await fetch(baseUrl + path, {
    method,
    ...(body instanceof FormData ? { body } : body ? { headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, body: await response.json() };
}

function ownPlant(t, overrides = {}) {
  const plant = new Plant({ _id: plantId, userId, name: 'Бамбук у окна', createdAt: new Date('2026-09-01T00:00:00Z'), ...overrides });
  t.mock.method(Plant, 'findOne', async () => plant);
  t.mock.method(plant, 'save', async () => plant);
  t.mock.method(Reminder, 'find', async () => []);
  t.mock.method(Reminder, 'updateOne', async () => ({ modifiedCount: 1 }));
  return plant;
}

test('invalid plant identifier returns actionable 400 without a database query', async () => {
  const response = await request('/not-an-id');
  assert.equal(response.status, 400);
  assert.match(response.body.error, /идентификатор/);
});

test('empty names and malformed care fail before creating a plant', async () => {
  assert.equal((await request('', 'POST', { name: '   ' })).status, 400);
  const response = await request('', 'POST', { name: 'Фикус', care: '{bad json' });
  assert.equal(response.status, 400);
});

test('saving owned scan trusts its diagnosis, preserves custom care, and creates first photo exactly once without spending quota', async (t) => {
  const scanId = new mongoose.Types.ObjectId();
  const baseline = [];
  t.mock.method(Scan, 'findOne', async () => ({ _id: scanId, plantId: null, imageUrl: '/uploads/scanned.jpg', result: {
    isPlant: true, isHealthy: false, healthScore: 35, severity: 'severe', species: 'Ficus elastica',
    diagnosis: { title: 'Повреждение листьев', description: 'Видимые повреждения' },
    careAdvice: { wateringIntervalDays: 3, fertilizerIntervalDays: 30 },
  } }));
  t.mock.method(Scan, 'updateOne', async () => ({ modifiedCount: 1 }));
  t.mock.method(Plant, 'create', async (data) => new Plant({ ...data, _id: plantId, createdAt: new Date() }));
  t.mock.method(JournalEntry, 'exists', async () => false);
  t.mock.method(JournalEntry, 'create', async (data) => { baseline.push(data); return data; });
  t.mock.method(Reminder, 'updateOne', async () => ({ modifiedCount: 1 }));
  t.mock.method(Reminder, 'find', async () => []);
  t.mock.method(scanQuota, 'run', () => assert.fail('scan must not be charged twice'));
  const response = await request('', 'POST', {
    name: 'Фикус на кухне', scanId: String(scanId), healthScore: 100, isHealthy: true,
    photoUrl: '/uploads/forged.jpg', care: { wateringIntervalDays: 10 },
  });
  assert.equal(response.status, 201);
  assert.equal(response.body.plant.healthScore, 35);
  assert.equal(response.body.plant.healthStatus, 'sick');
  assert.equal(response.body.plant.photoUrl, '/uploads/scanned.jpg');
  assert.equal(response.body.plant.care.wateringIntervalDays, 10);
  assert.equal(response.body.plant.care.checkupIntervalDays, 7);
  assert.deepEqual(response.body.plant.careManualFields, ['wateringIntervalDays']);
  assert.equal(baseline.length, 1);
  assert.equal(baseline[0].source, 'baseline');
  assert.equal(baseline[0].healthScore, 35);
});

test('already saved scan cannot silently create duplicate plants', async (t) => {
  t.mock.method(Scan, 'findOne', async () => ({ plantId, result: { isPlant: true } }));
  t.mock.method(Plant, 'create', async () => assert.fail('duplicate plant must not be created'));
  const response = await request('', 'POST', { name: 'Ещё один фикус', scanId: String(new mongoose.Types.ObjectId()) });
  assert.equal(response.status, 409);
});

test('rename preserves species and returns the chosen distinguishing name', async (t) => {
  const plant = ownPlant(t, { species: 'Ficus elastica' });
  const response = await request(`/${plantId}`, 'PATCH', { name: '  Фикус в спальне  ' });
  assert.equal(response.status, 200);
  assert.equal(response.body.plant.name, 'Фикус в спальне');
  assert.equal(response.body.plant.species, 'Ficus elastica');
  assert.equal(plant.save.mock.callCount(), 1);
  const invalid = await request(`/${plantId}`, 'PATCH', { care: { fertilizerIntervalDays: -2 } });
  assert.equal(invalid.status, 400);
});

test('care form sending every value pins only actual edits, and persisted pins protect the next AI check', async (t) => {
  const plant = ownPlant(t);
  const unchangedForm = plant.care.toObject();
  const unchanged = await request(`/${plantId}`, 'PATCH', { care: unchangedForm });
  assert.equal(unchanged.status, 200);
  assert.deepEqual(unchanged.body.plant.careManualFields, []);
  const response = await request(`/${plantId}`, 'PATCH', { care: { ...unchangedForm, wateringIntervalDays: 10, light: 'Восточное окно' } });
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.plant.careManualFields, ['wateringIntervalDays', 'light']);
  const restored = Plant.hydrate(plant.toObject());
  applyPlantAnalysis(restored, { isPlant: true, isHealthy: true, healthScore: 95, careAdvice: { wateringIntervalDays: 2, light: 'Тень', fertilizerIntervalDays: 45, waterAmountMl: 400 } });
  assert.equal(restored.care.wateringIntervalDays, 10);
  assert.equal(restored.care.light, 'Восточное окно');
  assert.equal(restored.care.fertilizerIntervalDays, 45);
  assert.equal(restored.care.waterAmountMl, 400);
  const again = await request(`/${plantId}`, 'PATCH', { care: plant.care.toObject() });
  assert.deepEqual(again.body.plant.careManualFields, ['wateringIntervalDays', 'light']);
});

test('fertilizer action clears overdue and resets notification/snooze, postponement never marks actual care', async (t) => {
  const plant = ownPlant(t, { lastFertilizedAt: new Date('2026-09-01T00:00:00Z'), fertilizingSnoozedUntil: new Date(), lastFertilizeNotifiedAt: new Date() });
  const response = await request(`/${plantId}/fertilize`, 'POST', {});
  assert.equal(response.status, 200);
  assert.equal(response.body.plant.needsFertilizer, false);
  assert.equal(response.body.plant.fertilizingSnoozedUntil, null);
  assert.equal(response.body.plant.lastFertilizeNotifiedAt, null);
  const actualFertilizedAt = plant.lastFertilizedAt.getTime();
  const postponed = await request(`/${plantId}/care/snooze`, 'POST', { type: 'fertilizing', days: 1 });
  assert.equal(postponed.status, 200);
  assert.equal(plant.lastFertilizedAt.getTime(), actualFertilizedAt);
  assert.ok(plant.fertilizingSnoozedUntil > new Date());
  const invalid = await request(`/${plantId}/care/snooze`, 'POST', { type: 'fertilizing', days: 0 });
  assert.equal(invalid.status, 400);
});

test('legacy plant detail includes initial photo and missed weekly slots without writing to database', async (t) => {
  const plant = ownPlant(t, { photoUrl: '/uploads/initial.jpg' });
  t.mock.method(JournalEntry, 'find', () => ({ sort: async () => [] }));
  const create = t.mock.method(JournalEntry, 'create', async () => assert.fail('GET must not write'));
  const response = await request(`/${plantId}`);
  assert.equal(response.status, 200);
  assert.equal(response.body.journal[0].source, 'baseline');
  assert.equal(response.body.journal[0].photoUrl, '/uploads/initial.jpg');
  assert.ok(response.body.weeklyHistory.some((week) => week.status === 'missed'));
  assert.equal(response.body.weeklyHistory.at(-1).status, 'upcoming');
  assert.equal(create.mock.callCount(), 0);
  assert.equal(plant.save.mock.callCount(), 0);
});

test('note-only journal remains available when scan quota is exhausted', async (t) => {
  ownPlant(t);
  t.mock.method(scanQuota, 'run', () => assert.fail('notes must not invoke quota or AI'));
  t.mock.method(JournalEntry, 'create', async (data) => ({ ...data, _id: 'entry', createdAt: new Date() }));
  const response = await request(`/${plantId}/journal`, 'POST', { note: 'Полил после высыхания грунта' });
  assert.equal(response.status, 201);
  assert.equal(response.body.entry.note, 'Полил после высыхания грунта');
  assert.equal(response.body.entry.photoUrl, null);
});

test('nonplant checkup produces recoverable 422 and never creates journal or changes plant state', async (t) => {
  const plant = ownPlant(t, { photoUrl: '/uploads/initial.jpg' });
  const before = plant.toObject();
  t.mock.method(scanQuota, 'run', async () => { throw new AnalysisError('На фото не найдено растение', 422, 'NOT_PLANT'); });
  t.mock.method(JournalEntry, 'create', async () => assert.fail('nonplant must not be journaled'));
  const image = await sharp({ create: { width: 2, height: 2, channels: 3, background: '#fff' } }).png().toBuffer();
  const form = new FormData();
  form.append('photo', new Blob([image], { type: 'image/png' }), 'table.png');
  const response = await request(`/${plantId}/checkup`, 'POST', form);
  assert.equal(response.status, 422);
  assert.equal(response.body.code, 'NOT_PLANT');
  assert.equal(plant.save.mock.callCount(), 0);
  assert.deepEqual(plant.toObject(), before);
});
