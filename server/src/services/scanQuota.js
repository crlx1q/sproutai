import { User } from '../models/User.js';
import { config } from '../config.js';
import { DAY_MS } from '../utils/plantCare.js';

export class AnalysisError extends Error {
  constructor(message, status = 502, code = 'AI_UNAVAILABLE') {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function quotaView(user, limit = config.freeScansPerMonth, now = new Date()) {
  const pro = user.plan === 'pro' && (!user.proUntil || new Date(user.proUntil) > now);
  return {
    plan: pro ? 'pro' : 'free',
    limit: pro ? null : limit,
    used: user.scansUsed || 0,
    remaining: pro ? null : Math.max(0, limit - (user.scansUsed || 0)),
  };
}

export function createScanQuota({ users = User, limit = config.freeScansPerMonth, clock = () => new Date() } = {}) {
  async function resetPeriod(userId) {
    const now = clock();
    await users.updateOne({
      _id: userId,
      $or: [{ scansPeriodStart: { $lte: new Date(now.getTime() - 30 * DAY_MS) } }, { scansPeriodStart: null }],
    }, { $set: { scansUsed: 0, scansPeriodStart: now } });
    return now;
  }

  async function view(user) {
    const now = await resetPeriod(user._id);
    const current = await users.findById(user._id);
    return quotaView(current, limit, now);
  }

  async function run(user, analyze, persist, { allowNonPlant = false } = {}) {
    const now = await resetPeriod(user._id);
    // Reserve atomically before the paid call: concurrent uploads cannot spend the same final scan.
    const reserved = await users.findOneAndUpdate({
      _id: user._id,
      $or: [
        { plan: 'pro', $or: [{ proUntil: null }, { proUntil: { $gt: now } }] },
        { scansUsed: { $lt: limit } },
      ],
    }, { $inc: { scansUsed: 1 } }, { new: true });
    if (!reserved) throw new AnalysisError('Лимит бесплатных сканов исчерпан. Оформите Pro для безлимита.', 402, 'SCAN_LIMIT');
    let completed = false;
    try {
      const result = await analyze();
      if (result?.isPlant !== true) {
        if (!allowNonPlant) throw new AnalysisError('На фото не найдено растение. Сделайте новое фото: история и состояние не изменены.', 422, 'NOT_PLANT');
        const refunded = { ...(reserved.toObject ? reserved.toObject() : reserved), scansUsed: reserved.scansUsed - 1 };
        return { result, value: null, quota: quotaView(refunded, limit, now) };
      }
      const value = await persist(result);
      completed = true;
      return { result, value, quota: quotaView(reserved, limit, now) };
    } finally {
      if (!completed) {
        await users.updateOne({
          _id: user._id,
          scansPeriodStart: reserved.scansPeriodStart,
          scansUsed: { $gt: 0 },
        }, { $inc: { scansUsed: -1 } });
      }
    }
  }
  return { view, run };
}

export const scanQuota = createScanQuota();
