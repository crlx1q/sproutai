import mongoose from 'mongoose';

const scanSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    plantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Plant', default: null },
    imageUrl: { type: String, required: true },
    result: { type: mongoose.Schema.Types.Mixed, required: true },
  },
  { timestamps: true }
);

export const Scan = mongoose.model('Scan', scanSchema);
