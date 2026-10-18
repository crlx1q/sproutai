import mongoose from 'mongoose';
import { CARE_FIELDS, careDueAt, weeklyCheckupDueAt } from '../utils/plantCare.js';

const diagnosisSchema = new mongoose.Schema(
  {
    isHealthy: Boolean,
    title: String,
    description: String,
    confidence: Number,
    treatmentPlan: [String],
    scanId: { type: mongoose.Schema.Types.ObjectId, ref: 'Scan' },
    scannedAt: Date,
  },
  { _id: false }
);

const plantSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name: { type: String, required: true, trim: true },
    species: { type: String, default: '' },
    location: { type: String, enum: ['indoor', 'outdoor'], default: 'indoor' },
    origin: { type: String, enum: ['existing', 'grown'], default: 'existing' },
    stage: {
      type: String,
      enum: ['seed', 'sprout', 'seedling', 'growing', 'mature', 'flowering'],
      default: 'mature',
    },
    plantedAt: { type: Date, default: null },
    growthGoal: { type: String, default: '' },
    photoUrl: { type: String, default: null },
    healthStatus: {
      type: String,
      enum: ['thriving', 'needs_attention', 'sick'],
      default: 'thriving',
    },
    healthScore: { type: Number, min: 0, max: 100, default: 90 },
    previousHealthScore: { type: Number, min: 0, max: 100, default: null },
    healthTrend: { type: String, enum: ['up', 'down', 'same', null], default: null },
    lastProgressNote: { type: String, default: '' },
    careManualFields: { type: [{ type: String, enum: CARE_FIELDS }], default: [] },
    care: {
      wateringIntervalDays: { type: Number, min: 1, max: 365, default: 7 },
      waterAmountMl: { type: Number, min: 1, max: 100000, default: 250 },
      light: { type: String, default: 'Непрямой свет' },
      fertilizerIntervalDays: { type: Number, min: 1, max: 365, default: 30 },
      temperature: { type: String, default: '18-24°C' },
      checkupIntervalDays: { type: Number, min: 1, max: 365, default: 7 },
    },
    lastWateredAt: { type: Date, default: null },
    lastFertilizedAt: { type: Date, default: null },
    wateringSnoozedUntil: { type: Date, default: null },
    fertilizingSnoozedUntil: { type: Date, default: null },
    lastWaterNotifiedAt: { type: Date, default: null },
    lastWaterDeliveredAt: { type: Date, default: null },
    waterNotificationLockUntil: { type: Date, default: null },
    lastFertilizeNotifiedAt: { type: Date, default: null },
    lastFertilizeDeliveredAt: { type: Date, default: null },
    fertilizeNotificationLockUntil: { type: Date, default: null },
    lastCheckupAt: { type: Date, default: null },
    nextCheckupAt: { type: Date, default: null },
    lastCheckupNotifiedAt: { type: Date, default: null },
    lastCheckupDeliveredAt: { type: Date, default: null },
    checkupNotificationLockUntil: { type: Date, default: null },
    lastDiagnosis: { type: diagnosisSchema, default: null },
  },
  { timestamps: true }
);

plantSchema.methods.wateringDueAt = function () {
  return careDueAt(this.lastWateredAt || this.createdAt, this.care.wateringIntervalDays, this.wateringSnoozedUntil);
};

plantSchema.methods.fertilizingDueAt = function () {
  return careDueAt(this.lastFertilizedAt || this.createdAt, this.care.fertilizerIntervalDays, this.fertilizingSnoozedUntil);
};

plantSchema.methods.checkupDueAt = function () {
  return weeklyCheckupDueAt(this);
};

export const Plant = mongoose.model('Plant', plantSchema);
