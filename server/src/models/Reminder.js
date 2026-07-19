import mongoose from 'mongoose';

const reminderSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    plantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Plant', required: true },
    type: { type: String, enum: ['watering', 'fertilizing'], required: true },
    intervalDays: { type: Number, required: true, min: 1 },
    nextDueAt: { type: Date, required: true },
    active: { type: Boolean, default: true },
  },
  { timestamps: true }
);

export const Reminder = mongoose.model('Reminder', reminderSchema);
