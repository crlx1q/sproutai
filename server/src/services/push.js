import { existsSync, readFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';
import { config } from '../config.js';
import { User } from '../models/User.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let app = null;
const status = { enabled: false, state: 'not_initialized', source: null, errorCode: null, lastSendAt: null, lastErrorAt: null };
const transientCodes = new Set(['messaging/server-unavailable', 'messaging/internal-error', 'messaging/unknown-error', 'app/network-error', 'ECONNRESET', 'ETIMEDOUT']);
const invalidTokenCodes = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);

/** Public diagnostics contain no credentials, tokens or provider error messages. */
export function getPushStatus() {
  return { ...status, enabled: !!app };
}

/** Инициализирует Firebase Admin SDK из service-account JSON. */
export function initPush() {
  if (app) return app;
  try {
    const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    const saPath = path.isAbsolute(config.firebaseServiceAccountPath)
      ? config.firebaseServiceAccountPath
      : path.resolve(__dirname, '../../', config.firebaseServiceAccountPath);
    let credential;
    let projectId = config.firebaseProjectId;
    if (inline) {
      status.source = 'inline';
      const account = JSON.parse(inline.startsWith('{') ? inline : Buffer.from(inline, 'base64').toString('utf8'));
      if (typeof account.private_key === 'string') account.private_key = account.private_key.replace(/\\n/g, '\n');
      credential = admin.credential.cert(account);
      projectId ||= account.project_id;
    } else if (existsSync(saPath)) {
      status.source = 'file';
      const account = JSON.parse(readFileSync(saPath, 'utf8'));
      credential = admin.credential.cert(account);
      projectId ||= account.project_id;
    } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS || config.firebaseUseApplicationDefault) {
      status.source = 'application_default';
      credential = admin.credential.applicationDefault();
    } else {
      status.state = 'disabled';
      status.errorCode = 'firebase_credentials_missing';
      console.warn('[push] Disabled: configure FIREBASE_SERVICE_ACCOUNT_JSON, FIREBASE_SERVICE_ACCOUNT or application-default credentials.');
      return null;
    }
    app = admin.apps.find((existing) => existing?.name === '[DEFAULT]') || admin.initializeApp({ credential, ...(projectId ? { projectId } : {}) });
    Object.assign(status, { enabled: true, state: 'ready', errorCode: null });
    console.log('[push] Firebase Admin initialized using', status.source);
  } catch (err) {
    Object.assign(status, { enabled: false, state: 'error', errorCode: err?.code || 'firebase_configuration_invalid', lastErrorAt: new Date().toISOString() });
    console.error('[push] Initialization failed:', status.errorCode);
    app = null;
  }
  return app;
}

export function isPushEnabled() {
  return !!app;
}

/** Retry only transient failures, never tokens that already succeeded. */
export async function deliverMulticast(messaging, message, { sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) } = {}) {
  const tokens = [...new Set(message.tokens.filter((token) => typeof token === 'string' && token.length > 0))];
  const result = { sent: 0, failed: 0, invalid: [], errors: {} };
  for (let offset = 0; offset < tokens.length; offset += 500) {
    let pending = tokens.slice(offset, offset + 500);
    for (let attempt = 0; pending.length && attempt < 2; attempt++) {
      let responses;
      try {
        responses = (await messaging.sendEachForMulticast({ ...message, tokens: pending })).responses;
      } catch (err) {
        responses = pending.map(() => ({ success: false, error: { code: err?.code || 'messaging/send-failed' } }));
      }
      const retry = [];
      responses.forEach((response, index) => {
        if (response.success) { result.sent++; return; }
        const code = response.error?.code || 'messaging/send-failed';
        if (attempt === 0 && transientCodes.has(code)) { retry.push(pending[index]); return; }
        result.failed++;
        result.errors[code] = (result.errors[code] || 0) + 1;
        // invalid-argument can mean a broken payload, so it must never delete tokens.
        if (invalidTokenCodes.has(code)) result.invalid.push(pending[index]);
      });
      pending = retry;
      if (pending.length) await sleep(1000);
    }
  }
  return result;
}

export async function sendToUser(userId, { title, body, data = {} }) {
  if (!app) return { sent: 0, failed: 0, reason: 'push_disabled' };
  const user = await User.findById(userId).select('fcmTokens isBlocked');
  if (!user || user.isBlocked || !user.fcmTokens?.length) return { sent: 0, failed: 0, reason: 'no_devices' };
  const stringData = Object.fromEntries(Object.entries(data).filter(([, value]) => value != null).map(([key, value]) => [key, String(value)]));
  const result = await deliverMulticast(admin.messaging(app), {
    tokens: user.fcmTokens,
    notification: { title, body },
    data: stringData,
    android: {
      priority: 'high',
      ttl: 24 * 60 * 60 * 1000,
      collapseKey: data.plantId ? `${data.type}:${data.plantId}` : 'sprout',
      notification: { channelId: 'watering', sound: 'default', ...(data.plantId ? { tag: `${data.type}:${data.plantId}` } : {}) },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  });
  if (result.invalid.length) await User.updateOne({ _id: userId }, { $pull: { fcmTokens: { $in: result.invalid } } });
  if (result.sent > 0) status.lastSendAt = new Date().toISOString();
  if (result.failed > 0) {
    status.lastErrorAt = new Date().toISOString();
    status.errorCode = Object.keys(result.errors)[0];
    console.warn('[push] Delivery failures:', JSON.stringify(result.errors));
  } else if (result.sent > 0) { status.errorCode = null; }
  return { sent: result.sent, failed: result.failed, errors: result.errors };
}
