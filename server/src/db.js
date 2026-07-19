import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import { config } from './config.js';
import { User } from './models/User.js';

export async function connectDb() {
  await mongoose.connect(config.mongoUri);
  console.log('[db] connected to MongoDB');
  await seedAdmin();
}

async function seedAdmin() {
  const existing = await User.findOne({ email: config.adminEmail });
  if (existing) {
    if (existing.role !== 'admin') {
      existing.role = 'admin';
      await existing.save();
    }
    return;
  }
  await User.create({
    email: config.adminEmail,
    passwordHash: await bcrypt.hash(config.adminPassword, 10),
    name: 'Admin',
    role: 'admin',
    plan: 'pro',
  });
  console.log('[db] admin user seeded');
}
