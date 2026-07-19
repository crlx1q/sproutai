// Разовый скрипт очистки: удаляет ВСЕ растения пользователя вместе со
// сканами, журналом роста и напоминаниями. Нужен для чистого старта после
// накопления тестовых данных.
//
// Использование:
//   cd server
//   node scripts/reset-plants.js you@example.com     // только этот пользователь
//   node scripts/reset-plants.js --all               // ВСЕ пользователи (осторожно!)
import 'dotenv/config';
import mongoose from 'mongoose';
import { config } from '../src/config.js';
import { User } from '../src/models/User.js';
import { Plant } from '../src/models/Plant.js';
import { Scan } from '../src/models/Scan.js';
import { JournalEntry } from '../src/models/JournalEntry.js';
import { Reminder } from '../src/models/Reminder.js';

const arg = process.argv[2];
const ALL = process.argv.includes('--all');

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function main() {
  if (!arg && !ALL) {
    console.error('Использование: node scripts/reset-plants.js <email>   (или --all для всех пользователей)');
    process.exit(1);
  }

  await mongoose.connect(config.mongoUri);

  let filter = {};
  if (!ALL) {
    const email = arg;
    const user = await User.findOne({ email: new RegExp(`^${escapeRegex(email)}$`, 'i') });
    if (!user) {
      console.error('Пользователь не найден:', email);
      await mongoose.disconnect();
      process.exit(1);
    }
    filter = { userId: user._id };
    console.log(`Чистим растения пользователя ${email} (${user._id})`);
  } else {
    console.log('ВНИМАНИЕ: удаляем растения ВСЕХ пользователей');
  }

  const [p, s, j, r] = await Promise.all([
    Plant.deleteMany(filter),
    Scan.deleteMany(filter),
    JournalEntry.deleteMany(filter),
    Reminder.deleteMany(filter),
  ]);

  console.log(
    `Удалено: растений ${p.deletedCount}, сканов ${s.deletedCount}, ` +
    `записей журнала ${j.deletedCount}, напоминаний ${r.deletedCount}`
  );

  await mongoose.disconnect();
  console.log('Готово ✅');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
