import { GoogleGenAI, Type } from '@google/genai';
import { config } from '../config.js';

const ai = new GoogleGenAI({ apiKey: config.geminiApiKey });

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
      description: 'Через сколько дней сделать новое контрольное фото. Проблемные — 3-7, здоровые — 14-30',
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
- 90-100 (severity=none): растение идеально, никаких проблем.
- 70-89 (severity=mild): лёгкие проблемы (1-2 жёлтых листа, лёгкий стресс, суховато).
- 50-69 (severity=moderate): заметная проблема, нужно вмешательство
  (дефицит, начало заражения вредителем, коркование почвы, стресс черенка/пересадки).
- 30-49 (severity=severe): серьёзная болезнь, поражена часть растения.
- 5-29 (severity=critical): растение погибает, поражение сильное.
Если видишь ЛЮБУЮ проблему — балл ОБЯЗАН быть ниже 85, а isHealthy=false.
Балл и severity должны соответствовать друг другу по рубрике.

Поле nextCheckupDays: чем хуже состояние, тем скорее контроль
(critical/severe: 3-5 дней, moderate: 5-7, mild: 10-14, none: 14-30).

Если на фото нет растения — верни isPlant=false и пустые/нулевые значения.`;

const SEVERITY_BANDS = {
  none: [85, 100],
  mild: [70, 84],
  moderate: [50, 69],
  severe: [30, 49],
  critical: [5, 29],
};

/**
 * Приводим ответ модели к согласованному виду: балл здоровья не может
 * противоречить найденной проблеме. Это лечит «оптимизм» модели,
 * из-за которого раньше почти все растения получали ~90%.
 */
export function reconcileHealth(result) {
  if (!result || result.isPlant === false) return result;

  let severity = String(result.severity || '').toLowerCase();
  let score = Number(result.healthScore);
  if (!Number.isFinite(score)) score = 80;
  score = Math.max(0, Math.min(100, Math.round(score)));

  // Если severity не распознан — выводим из балла.
  if (!SEVERITY_BANDS[severity]) {
    severity =
      score >= 85 ? 'none'
        : score >= 70 ? 'mild'
          : score >= 50 ? 'moderate'
            : score >= 30 ? 'severe'
              : 'critical';
  }

  // Если модель нашла проблему, но поставила завышенный балл —
  // опускаем балл в диапазон, соответствующий severity.
  const [lo, hi] = SEVERITY_BANDS[severity];
  if (score < lo) score = lo;
  if (score > hi) score = hi;

  const isHealthy = severity === 'none';

  let checkup = Number(result.nextCheckupDays);
  if (!Number.isFinite(checkup) || checkup < 1) {
    checkup = isHealthy ? 21 : severity === 'mild' ? 12 : severity === 'moderate' ? 6 : 4;
  }
  checkup = Math.max(2, Math.min(45, Math.round(checkup)));

  return { ...result, healthScore: score, severity, isHealthy, nextCheckupDays: checkup };
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
  { previousDiagnosis = null, plantContext = null, mode = 'diagnose' } = {}
) {
  const parts = [
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
      text: `Предыдущий диагноз этого растения (${previousDiagnosis.scannedAt}): ${previousDiagnosis.title}. ${previousDiagnosis.description}. Сравни с текущим фото и опиши динамику в progressNote (стало лучше/хуже/без изменений и почему).`,
    });
  }

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

  return reconcileHealth(JSON.parse(response.text));
}
