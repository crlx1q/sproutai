import test from 'node:test';
import assert from 'node:assert/strict';
import { createScanQuota, quotaView } from '../src/services/scanQuota.js';
import { DAY_MS } from '../src/utils/plantCare.js';

const now = new Date('2026-10-18T10:00:00Z');
function matches(document, filter) {
  return Object.entries(filter).every(([key, value]) => {
    if (key === '$or') return value.some((option) => matches(document, option));
    const actual = document[key];
    if (value === null) return actual == null;
    if (value && typeof value === 'object' && !(value instanceof Date)) {
      return Object.entries(value).every(([operator, expected]) => ({
        $lt: () => actual < expected, $lte: () => actual <= expected, $gt: () => actual > expected,
      })[operator]());
    }
    return value instanceof Date ? actual?.getTime() === value.getTime() : actual === value;
  });
}
function fixture(extra = {}) {
  const user = { _id: 'user1', plan: 'free', scansUsed: 0, scansPeriodStart: now, ...extra };
  const users = {
    async updateOne(filter, update) {
      if (!matches(user, filter)) return { modifiedCount: 0 };
      Object.assign(user, update.$set || {});
      for (const [key, increment] of Object.entries(update.$inc || {})) user[key] += increment;
      return { modifiedCount: 1 };
    },
    async findOneAndUpdate(filter, update) {
      if (!matches(user, filter)) return null;
      for (const [key, increment] of Object.entries(update.$inc || {})) user[key] += increment;
      return structuredClone(user);
    },
    async findById() { return structuredClone(user); },
  };
  return { user, quota: createScanQuota({ users, limit: 5, clock: () => now }) };
}

test('last free scan is reserved once under concurrent requests; second call never invokes AI', async () => {
  const { user, quota } = fixture({ scansUsed: 4 });
  let calls = 0;
  const analyze = async () => { calls++; return { isPlant: true }; };
  const outcomes = await Promise.allSettled([
    quota.run(user, analyze, async () => 'saved'), quota.run(user, analyze, async () => 'saved'),
  ]);
  assert.equal(calls, 1);
  assert.equal(outcomes.filter((o) => o.status === 'fulfilled').length, 1);
  assert.equal(outcomes.find((o) => o.status === 'rejected').reason.code, 'SCAN_LIMIT');
  assert.equal(user.scansUsed, 5);
});

test('AI error or persistence failure refunds the reservation', async () => {
  for (const failAt of ['analyze', 'persist']) {
    const { user, quota } = fixture({ scansUsed: 4 });
    await assert.rejects(quota.run(user,
      async () => { if (failAt === 'analyze') throw new Error('AI unavailable'); return { isPlant: true }; },
      async () => { throw new Error('Database unavailable'); }), /unavailable/);
    assert.equal(user.scansUsed, 4);
  }
});

test('nonplant checkup refunds scan and never persists or updates schedule', async () => {
  const { user, quota } = fixture();
  let persisted = false;
  await assert.rejects(quota.run(user, async () => ({ isPlant: false }), async () => { persisted = true; }), { code: 'NOT_PLANT', status: 422 });
  assert.equal(persisted, false);
  assert.equal(user.scansUsed, 0);
});

test('ordinary scanner can display a nonplant result without charging or creating a history record', async () => {
  const { user, quota } = fixture({ scansUsed: 3 });
  const outcome = await quota.run(user, async () => ({ isPlant: false }), async () => assert.fail('must not save'), { allowNonPlant: true });
  assert.equal(outcome.result.isPlant, false);
  assert.equal(outcome.value, null);
  assert.equal(outcome.quota.remaining, 2);
  assert.equal(user.scansUsed, 3);
});

test('expired plan is limited, active and lifetime Pro are unlimited', async () => {
  const expired = fixture({ plan: 'pro', proUntil: new Date(now.getTime() - 1), scansUsed: 5 });
  await assert.rejects(expired.quota.run(expired.user, async () => assert.fail('no AI'), async () => {}), { code: 'SCAN_LIMIT' });
  for (const proUntil of [null, new Date(now.getTime() + DAY_MS)]) {
    const { user, quota } = fixture({ plan: 'pro', proUntil, scansUsed: 50 });
    const outcome = await quota.run(user, async () => ({ isPlant: true }), async () => 'saved');
    assert.equal(outcome.quota.remaining, null);
    assert.equal(user.scansUsed, 51);
  }
});

test('30-day period resets exactly at boundary, quota view does not spend scans', async () => {
  const { user, quota } = fixture({ scansUsed: 5, scansPeriodStart: new Date(now.getTime() - 30 * DAY_MS) });
  assert.deepEqual(await quota.view(user), { plan: 'free', limit: 5, used: 0, remaining: 5 });
  assert.equal(user.scansUsed, 0);
  assert.equal(user.scansPeriodStart.getTime(), now.getTime());
  assert.equal((await quota.view(user)).remaining, 5);
  assert.equal(quotaView({ plan: 'free', scansUsed: 99 }, 5, now).remaining, 0);
});
