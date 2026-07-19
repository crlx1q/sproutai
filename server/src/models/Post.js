import mongoose from 'mongoose';

const postSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    plantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Plant', default: null },
    imageUrl: { type: String, default: null },
    text: { type: String, required: true, trim: true },
    likes: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
    commentsCount: { type: Number, default: 0 },
  },
  { timestamps: true }
);

export const Post = mongoose.model('Post', postSchema);
