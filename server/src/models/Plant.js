import mongoose from 'mongoose';

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
    photoUrl: { type: String, default: null },
    healthStatus: {
      type: String,
      enum: ['thriving', 'needs_attention', 'sick'],
      default: 'thriving',
    },
    healthScore: { type: Number, min: 0, max: 100, default: 90 },
    care: {
      wateringIntervalDays: { type: Number, default: 7 },
      waterAmountMl: { type: Number, default: 250 },
      light: { type: String, default: 'Непрямой свет' },
      fertilizerIntervalDays: { type: Number, default: 30 },
      temperature: { type: String, default: '18-24°C' },
    },
    lastWateredAt: { type: Date, default: null },
    lastFertilizedAt: { type: Date, default: null },
    lastWaterNotifiedAt: { type: Date, default: null },
    lastFertilizeNotifiedAt: { type: Date, default: null },
    lastDiagnosis: { type: diagnosisSchema, default: null },
  },
  { timestamps: true }
);

plantSchema.methods.wateringDueAt = function () {
  const base = this.lastWateredAt || this.createdAt;
  return new Date(base.getTime() + this.care.wateringIntervalDays * 86400000);
};

plantSchema.methods.fertilizingDueAt = function () {
  const base = this.lastFertilizedAt || this.createdAt;
  return new Date(base.getTime() + this.care.fertilizerIntervalDays * 86400000);
};

export const Plant = mongoose.model('Plant', plantSchema);
