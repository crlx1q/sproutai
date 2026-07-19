import { readFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';
import { config } from '../config.js';
import { User } from '../models/User.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let app = null;

/** Инициализирует Firebase Admin SDK из service-account JSON. */
export function initPush() {
  if (app) return app;
  try {
    let serviceAccount;
    const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (inlineJson && inlineJson.trim()) {
      // На Heroku ключ передаётся через Config Var (сырой JSON или base64).
      const text = inlineJson.trim().startsWith('{')
        ? inlineJson
        : Buffer.from(inlineJson, 'base64').toString('utf8');
      serviceAccount = JSON.parse(text);
    } else {
      const saPath = path.isAbsolute(config.firebaseServiceAccountPath)
        ? config.firebaseServiceAccountPath
        : path.resolve(__dirname, '../../', config.firebaseServiceAccountPath);
      serviceAccount = JSON.parse(readFileSync(saPath, 'utf8'));
    }
    app = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log('[push] Firebase Admin initialized for', serviceAccount.project_id);
  } catch (err) {
    console.warn('[push] Firebase disabled:', err.message);
    app = null;
  }
  return app;
}

export function isPushEnabled() {
  return !!app;
}

/**
 * Отправляет пуш пользователю на все его устройства.
 * Невалидные токены автоматически удаляются из профиля.
 */
export async function sendToUser(userId, { title, body, data = {} }) {
  if (!app) return { sent: 0, failed: 0 };
  const user = await User.findById(userId).select('fcmTokens');
  if (!user || !user.fcmTokens || !user.fcmTokens.length) return { sent: 0, failed: 0 };

  const stringData = {};
  for (const [k, v] of Object.entries(data)) stringData[k] = String(v);

  const res = await admin.messaging().sendEachForMulticast({
    tokens: user.fcmTokens,
    notification: { title, body },
    data: stringData,
    android: {
      priority: 'high',
      notification: { channelId: 'watering', sound: 'default' },
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
  });

  const invalid = [];
  res.responses.forEach((r, i) => {
    if (!r.success) {
      const code = (r.error && r.error.code) || '';
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument'
      ) {
        invalid.push(user.fcmTokens[i]);
      }
    }
  });
  if (invalid.length) {
    await User.updateOne({ _id: userId }, { $pull: { fcmTokens: { $in: invalid } } });
  }
  return { sent: res.successCount, failed: res.failureCount };
}
