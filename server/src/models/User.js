import mongoose from 'mongoose';

const userSchema = new mongoose.Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true },
    name: { type: String, required: true, trim: true },
    avatarUrl: { type: String, default: null },
    role: { type: String, enum: ['user', 'admin'], default: 'user' },
    plan: { type: String, enum: ['free', 'pro'], default: 'free' },
    proUntil: { type: Date, default: null },
    scansUsed: { type: Number, default: 0 },
    scansPeriodStart: { type: Date, default: () => new Date() },
    isBlocked: { type: Boolean, default: false },
    fcmTokens: { type: [String], default: [] },
  },
  { timestamps: true }
);

userSchema.methods.toPublic = function () {
  return {
    id: this._id,
    email: this.email,
    name: this.name,
    avatarUrl: this.avatarUrl,
    role: this.role,
    plan: this.plan,
    proUntil: this.proUntil,
    scansUsed: this.scansUsed,
    createdAt: this.createdAt,
  };
};

export const User = mongoose.model('User', userSchema);
