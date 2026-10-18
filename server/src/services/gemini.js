import { GoogleGenAI, Type } from '@google/genai';
import { config } from '../config.js';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { reconcileHealth } from '../utils/healthAnalysis.js';
export { reconcileHealth } from '../utils/healthAnalysis.js';

let ai;

export const GROWTH_STAGES = ['seed', 'sprout', 'seedling', 'growing', 'mature', 'flowering'];

const responseSchema = {
  type: Type.OBJECT,
  properties: {
    isPlant: { type: Type.BOOLEAN, description: 'Есть ли на фото растение' },
    species: { type: Type.STRING, description: 'Латинское название вида' },
    commonName: { type: Type.STRING, description: 'Распространённое название на русском' },
    isHealthy: { type: Type.BOOLEAN, description: 'true ТОЛЬКО если проблем нет совсем' },
    severity: {
      type: Type.STRING,
      description: 'Тяжесть состояния: строго одно из "none", "mild", "moderate", "severe", "critical"',
    },
    healthScore: { type: Type.INTEGER, description: 'Честная оценка здоровья 0-100 строго по рубрике' },
    growthStage: {
      type: Type.STRING,
      description: 'Стадия роста: одно из "seed", "sprout", "seedling", "growing", "mature", "flowering"',
    },
    diagnosis: {
      type: Type.OBJECT,
      properties: {
        title: { type: Type.STRING, description: 'Краткое название проблемы или "Здоровое растение"' },
        description: { type: Type.STRING, description: '2-4 предложения: что видно и почему' },
        confidence: { type: Type.NUMBER, description: 'Уверенность 0-1' },
      },
      required: ['title', 'description', 'confidence'],
    },
    treatmentPlan: {
      type: Type.ARRAY,
      items: { type: Type.STRING },
      description: 'Пошаговый план лечения, пустой если растение здорово',
    },
    growthAdvice: {
      type: Type.ARRAY,
      items: { type: Type.STRING },
      description: '2-4 конкретных шага, что сделать до следующей проверки для роста и восстановления',
    },
    careAdvice: {
      type: Type.OBJECT,
      properties: {
        wateringIntervalDays: { type: Type.INTEGER },
        waterAmountMl: { type: Type.INTEGER, description: 'Сколько мл воды за один полив для растения такого размера' },
        watering: { type: Type.STRING, description: 'Совет по поливу одной фразой' },
        light: { type: Type.STRING },
        fertilizer: { type: Type.STRING },
        fertilizerIntervalDays: { type: Type.INTEGER },
        temperature: { type: Type.STRING, description: 'Например "18-24°C"' },
      },
      required: ['wateringIntervalDays', 'waterAmountMl', 'watering', 'light', 'fertilizer', 'fertilizerIntervalDays', 'temperature'],
    },
    nextCheckupDays: {
      type: Type.INTEGER,
      description: 'Следующее плановое контрольное фото через 7 дней',
    },
    progressNote: {
      type: Type.STRING,
      description: 'Если дан предыдущий диагноз — оценка динамики (лучше/хуже/без изменений и почему), иначе пустая строка',
    },
  },
  required: ['isPlant', 'species', 'commonName', 'isHealthy', 'severity', 'healthScore', 'growthStage', 'diagnosis', 'treatmentPlan', 'careAdvice', 'nextCheckupDays'],
};

const SYSTEM_PROMPT = `Ты — опытный ботаник и фитопатолог приложения Sprout AI.
По фотографии растения определи вид, стадию роста, ЧЕСТНО оцени здоровье,
диагностируй проблемы (дефициты питания, вредители, грибок, гнили,
перелив/недолив, солнечные ожоги, коркование почвы, стресс черенка/пересадки)
и составь план ухода и роста. Отвечай на русском языке, кратко и конкретно.

КРИТИЧЕСКИ ВАЖНО про оценку здоровья — НЕ ЗАВЫШАЙ баллы. Большинство фото
получают ~90 по ошибке. Используй рубрику строго и честно:
- 85-100 (severity=none): растение здорово, видимых проблем нет.
- 70-84 (severity=mild): лёгкие проблемы (1-2 жёлтых листа, лёгкий стресс, суховато).
- 50-69 (severity=moderate): заметная проблема, нужно вмешательство
  (дефицит, начало заражения вредителем, коркование почвы, стресс черенка/пересадки).
- 30-49 (severity=severe): серьёзная болезнь, поражена часть растения.
- 5-29 (severity=critical): растение погибает, поражение сильное.
Если видишь ЛЮБУЮ проблему — балл ОБЯЗАН быть ниже 85, а isHealthy=false.
Балл и severity должны соответствовать друг другу по рубрике.

Поле nextCheckupDays всегда 7: приложение ведёт еженедельную историю.
Если состояние опасное, отдельно напиши срочные действия в treatmentPlan.

Динамика и текущее здоровье — разные вещи. «Стало лучше» не означает,
что растение уже здорово: перечисли оставшиеся видимые симптомы.
Если старые симптомы исчезли, isHealthy=true, severity=none и старый план
лечения больше не нужен. Не сохраняй прошлую проблему автоматически.
Не выводи диагноз пересадки только из прошлой записи: нужны текущие признаки.
Не утверждай, что растение выросло или проблема уменьшилась, если это
нельзя увидеть на сопоставимых фото; укажи ограничения сравнения.

Если на фото нет растения — верни isPlant=false и пустые/нулевые значения.`;

async function previousPhotoBytes(photoUrl) {
  if (typeof photoUrl !== 'string') return null;
  try {
    if (/^\/uploads\/[a-zA-Z0-9-]+\.jpg$/.test(photoUrl)) {
      const uploadsDir = fileURLToPath(new URL('../../uploads/', import.meta.url));
      const file = path.join(uploadsDir, path.basename(photoUrl));
      const info = await fs.stat(file);
      return info.size <= 6 * 1024 * 1024 ? await fs.readFile(file) : null;
    }
    const url = new URL(photoUrl);
    // Only our configured image store is fetchable; plant.photoUrl is client-controlled.
    if (url.protocol !== 'https:' || url.hostname !== 'res.cloudinary.com' ||
      url.pathname.split('/')[1] !== config.cloudinary.cloudName || url.username || url.password) return null;
    const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(6000) });
    if (!response.ok || !response.headers.get('content-type')?.startsWith('image/')) return null;
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > 6 * 1024 * 1024) throw new Error('Image too large');
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  } catch {
    // An unavailable old image must not prevent taking a new photo.
    return null;
  }
}

/**
 * Анализ фото растения.
 * @param {Buffer} jpegBuffer — сжатый jpeg.
 * @param {object} opts
 * @param {object|null} opts.previousDiagnosis — прошлый диагноз для оценки динамики.
 * @param {object|null} opts.plantContext — имя/вид/место/стадия/дата посадки.
 * @param {'diagnose'|'grow'|'checkup'} opts.mode — режим анализа.
 */
export async function analyzePlantImage(
  jpegBuffer,
  { previousDiagnosis = null, previousHealthScore = null, previousPhotoUrl = null, careEvents = null, plantContext = null, mode = 'diagnose' } = {}
) {
  const previousImage = await previousPhotoBytes(previousPhotoUrl);
  const parts = [
    ...(previousImage ? [
      { text: 'ПРЕДЫДУЩЕЕ фото этого растения для сравнения:' },
      { inlineData: { mimeType: 'image/jpeg', data: previousImage.toString('base64') } },
    ] : []),
    { text: 'ТЕКУЩЕЕ фото. Оцени текущее здоровье именно по нему:' },
    { inlineData: { mimeType: 'image/jpeg', data: jpegBuffer.toString('base64') } },
    { text: 'Проанализируй растение на фото.' },
  ];

  if (plantContext) {
    const bits = [];
    if (plantContext.name) bits.push(`имя «${plantContext.name}»`);
    if (plantContext.species) bits.push(`вид ${plantContext.species}`);
    if (plantContext.location) bits.push(`место: ${plantContext.location === 'outdoor' ? 'улица' : 'помещение'}`);
    if (plantContext.stage) bits.push(`заявленная стадия: ${plantContext.stage}`);
    if (plantContext.plantedAt) bits.push(`посажено: ${plantContext.plantedAt}`);
    if (bits.length) parts.push({ text: `Контекст растения — ${bits.join(', ')}.` });
  }

  if (mode === 'grow') {
    parts.push({
      text: 'Пользователь выращивает это растение с нуля вместе с приложением. Определи стадию роста в growthStage и дай в growthAdvice конкретные шаги, чтобы оно росло здоровым до следующей проверки.',
    });
  }

  if (previousDiagnosis) {
    parts.push({
      text: `Предыдущий диагноз этого растения (${previousDiagnosis.scannedAt}): ${previousDiagnosis.title}. ${previousDiagnosis.description}. Прошлая оценка здоровья: ${previousHealthScore ?? 'неизвестна'}/100. ${previousImage ? 'Сопоставь предыдущее и текущее фото.' : 'Предыдущее фото недоступно; сравнение только с описанием, не заявляй визуальное подтверждение динамики.'} Опиши динамику в progressNote и отдельно оставшиеся проблемы.`,
    });
  }
  if (careEvents) parts.push({ text: `Отмеченный пользователем уход (не доказывает выздоровление): ${JSON.stringify(careEvents)}.` });

  ai ||= new GoogleGenAI({
    apiKey: config.geminiApiKey,
    // Finish before the app's receive timeout; SDK defaults can otherwise retry five times.
    httpOptions: { timeout: 45000, retryOptions: { attempts: 1 } },
  });
  const response = await ai.models.generateContent({
    model: config.geminiModel,
    contents: [{ role: 'user', parts }],
    config: {
      systemInstruction: SYSTEM_PROMPT,
      responseMimeType: 'application/json',
      responseSchema,
      temperature: 0.2,
    },
  });

  return { ...reconcileHealth(JSON.parse(response.text)), comparisonBasis: previousImage ? 'photos' : previousDiagnosis ? 'description' : 'initial' };
}
