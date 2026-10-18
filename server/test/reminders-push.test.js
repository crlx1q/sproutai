import test from 'node:test';
import assert from 'node:assert/strict';
import { createReminderRunner } from '../src/services/scheduler.js';
import { deliverMulticast } from '../src/services/push.js';

const now = new Date('2026-10-18T12:00:00Z');
const past = new Date('2026-10-17T12:00:00Z');
const future = new Date('2026-10-19T12:00:00Z');

function plant(id = 'plant1') {
  return {
    _id: id, userId: 'user1', name: 'Фикус',
    wateringDueAt: () => past,
    fertilizingDueAt: () => future,
    checkupDueAt: () => future,
  };
}

function harness(overrides = {}) {
  const current = plant();
  const sent = [];
  const finished = [];
  const errors = [];
  const run = createReminderRunner({
    enabled: () => true,
    plants: () => [current],
    disabledReminders: async () => [],
    claim: async () => future,
    finish: async (item, kind, lease, sentAt) => {
      finished.push({ type: kind.type, sentAt });
      if (sentAt) item[kind.sent] = sentAt;
    },
    send: async (userId, message) => { sent.push(message); return { sent: 1, failed: 0 }; },
    clock: () => now,
    onError: (error) => errors.push(error),
    ...overrides,
  });
  return { current, run, sent, finished, errors };
}

test('zero-device/failed deliveries remain retryable instead of consuming a care cycle', async () => {
  const h = harness({ send: async () => ({ sent: 0, failed: 1 }) });
  await h.run();
  await h.run();
  assert.equal(h.finished.length, 2);
  assert.ok(h.finished.every((entry) => entry.sentAt === null));
});

test('successful watering is recorded once; new care cycle can notify again', async () => {
  const h = harness();
  await h.run();
  await h.run();
  assert.equal(h.sent.length, 1);
  assert.equal(h.finished[0].sentAt, now);
  h.current.lastWaterDeliveredAt = null;
  await h.run();
  assert.equal(h.sent.length, 2);
  assert.equal(h.sent[0].data.dueAt, past.toISOString());
});

test('legacy notified timestamps from failed old deliveries do not suppress recovery', async () => {
  const h = harness();
  h.current.lastWaterNotifiedAt = now;
  await h.run();
  assert.equal(h.sent.length, 1);
  assert.equal(h.current.lastWaterDeliveredAt, now);
});

test('disabled preferences suppress every type, while missing records default enabled', async () => {
  const item = plant();
  item.fertilizingDueAt = () => past;
  item.checkupDueAt = () => past;
  const h = harness({
    plants: () => [item],
    disabledReminders: async () => [{ plantId: item._id, type: 'watering' }, { plantId: item._id, type: 'checkup' }],
  });
  await h.run();
  assert.deepEqual(h.sent.map((entry) => entry.data.type), ['fertilizing']);
});

test('future/snoozed due dates are not sent; an unavailable lease is respected', async () => {
  const item = plant();
  item.wateringDueAt = () => future;
  const h = harness({ plants: () => [item] });
  await h.run();
  assert.equal(h.sent.length, 0);
  item.wateringDueAt = () => past;
  const locked = harness({ claim: async () => null });
  await locked.run();
  assert.equal(locked.sent.length, 0);
});

test('one running pass prevents overlapping send work', async () => {
  let release;
  const wait = new Promise((resolve) => { release = resolve; });
  const h = harness({ send: async () => { await wait; return { sent: 1 }; } });
  const first = h.run();
  await new Promise((resolve) => setImmediate(resolve));
  await h.run();
  release();
  await first;
  assert.equal(h.finished.length, 1);
});

test('send exceptions release lease and do not stop other plants', async () => {
  let calls = 0;
  const h = harness({
    plants: () => [plant('first'), plant('second')],
    send: async () => { if (++calls === 1) throw new Error('offline'); return { sent: 1 }; },
  });
  await h.run();
  assert.equal(h.errors.length, 1);
  assert.deepEqual(h.finished.map((entry) => entry.sentAt), [null, now]);
});

test('disabled push integration does not query plants or mark reminders', async () => {
  const h = harness({ enabled: () => false, plants: () => { throw new Error('must not query'); } });
  await h.run();
  assert.equal(h.finished.length, 0);
  assert.equal(h.errors.length, 0);
});

test('multicast retries only transient failures without resending successful tokens', async () => {
  const calls = [];
  const messaging = { sendEachForMulticast: async ({ tokens }) => {
    calls.push(tokens);
    return { responses: tokens.map((token) => token === 'temporary' && calls.length === 1
      ? { success: false, error: { code: 'messaging/server-unavailable' } }
      : token === 'expired'
        ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
        : token === 'payload'
          ? { success: false, error: { code: 'messaging/invalid-argument' } }
          : { success: true }) };
  } };
  const result = await deliverMulticast(messaging, { tokens: ['ok', 'temporary', 'expired', 'payload', 'ok'] }, { sleep: async () => {} });
  assert.deepEqual(calls, [['ok', 'temporary', 'expired', 'payload'], ['temporary']]);
  assert.equal(result.sent, 2);
  assert.equal(result.failed, 2);
  assert.deepEqual(result.invalid, ['expired']);
});

test('multicast batches at the FCM limit and bounds transient whole-request retries', async () => {
  const sizes = [];
  const result = await deliverMulticast({ sendEachForMulticast: async ({ tokens }) => {
    sizes.push(tokens.length);
    return { responses: tokens.map(() => ({ success: true })) };
  } }, { tokens: Array.from({ length: 501 }, (_, i) => String(i)) });
  assert.deepEqual(sizes, [500, 1]);
  assert.equal(result.sent, 501);
  let attempts = 0;
  const failed = await deliverMulticast({ sendEachForMulticast: async () => {
    attempts++;
    throw Object.assign(new Error('offline'), { code: 'messaging/server-unavailable' });
  } }, { tokens: ['one'] }, { sleep: async () => {} });
  assert.equal(attempts, 2);
  assert.equal(failed.failed, 1);
  assert.deepEqual(failed.invalid, []);
});
