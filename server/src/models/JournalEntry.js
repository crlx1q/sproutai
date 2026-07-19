import mongoose from 'mongoose';

const journalEntrySchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    plantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Plant', required: true, index: true },
    photoUrl: { type: String, default: null },
    note: { type: String, default: '' },
    kind: { type: String, enum: ['before', 'after', 'progress'], default: 'progress' },
    healthScore: { type: Number, min: 0, max: 100, default: null },
    healthStatus: { type: String, enum: ['thriving', 'needs_attention', 'sick', null], default: null },
    analysis: { type: String, default: '' },
    trend: { type: String, enum: ['up', 'down', 'same', null], default: null },
  },
  { timestamps: true }
);

export const JournalEntry = mongoose.model('JournalEntry', journalEntrySchema);
