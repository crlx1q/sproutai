import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { requireAuth } from '../src/middleware/auth.js';
import { User } from '../src/models/User.js';
import { config } from '../src/config.js';

const subject = '507f1f77bcf86cd799439011';
function request(token) {
  const req = { headers: token ? { authorization: `Bearer ${token}` } : {} };
  const res = {
    statusCode: null, payload: null,
    status(code) { this.statusCode = code; return this; },
    json(value) { this.payload = value; return this; },
  };
  const nextCalls = [];
  return { req, res, nextCalls, next: (error) => nextCalls.push(error) };
}
const token = (extra = {}, options = {}) => jwt.sign({ sub: subject, ...extra }, config.jwtSecret, options);

test('temporary database failure goes to server error handler instead of returning 401', async (t) => {
  const failure = new Error('Mongo temporarily unavailable');
  t.mock.method(User, 'findById', async () => { throw failure; });
  const flow = request(token());
  await requireAuth(flow.req, flow.res, flow.next);
  assert.equal(flow.res.statusCode, null);
  assert.deepEqual(flow.nextCalls, [failure]);
  assert.equal(flow.req.user, undefined);
});

test('missing, invalid, expired, or malformed-subject JWT returns 401 without a database lookup', async (t) => {
  const query = t.mock.method(User, 'findById', async () => assert.fail('JWT validation must precede DB'));
  for (const value of [null, 'invalid', token({}, { expiresIn: -1 }), token({ sub: 'invalid' })]) {
    const flow = request(value);
    await requireAuth(flow.req, flow.res, flow.next);
    assert.equal(flow.res.statusCode, 401);
    assert.equal(flow.nextCalls.length, 0);
  }
  assert.equal(query.mock.callCount(), 0);
});

test('existing blocked user returns 403, deleted user returns 401', async (t) => {
  const query = t.mock.method(User, 'findById', async () => ({ isBlocked: true }));
  const blocked = request(token());
  await requireAuth(blocked.req, blocked.res, blocked.next);
  assert.equal(blocked.res.statusCode, 403);
  query.mock.mockImplementation(async () => null);
  const deleted = request(token());
  await requireAuth(deleted.req, deleted.res, deleted.next);
  assert.equal(deleted.res.statusCode, 401);
});

test('valid token resolves authoritative user and continues once', async (t) => {
  const user = { _id: subject, role: 'user', isBlocked: false };
  t.mock.method(User, 'findById', async () => user);
  const flow = request(token({ role: 'admin' }));
  await requireAuth(flow.req, flow.res, flow.next);
  assert.equal(flow.req.user, user);
  assert.equal(flow.req.user.role, 'user');
  assert.deepEqual(flow.nextCalls, [undefined]);
  assert.equal(flow.res.statusCode, null);
});
