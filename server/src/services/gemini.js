import { GoogleGenAI, Type } from '@google/genai';
import { config } from '../config.js';

const ai = new GoogleGenAI({ apiKey: config.geminiApiKey });

const responseSchema = {
  type: Type.OBJECT,
  properties: {
    isPlant: { type: Type.BOOLEAN, description: 'Есть ли на фото растение' },
    species: { type: Type.STRING, description: 'Латинское название вида' },
    commonName: { type: Type.STRING, description: 'Распространённое название на русском' },
    isHealthy: { type: Type.BOOLEAN },
    healthScore: { type: Type.INTEGER, description: 'Оценка здоровья 0-100' },
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
    progressNote: {
      type: Type.STRING,
      description: 'Если дан предыдущий диагноз — оценка динамики лечения, иначе пустая строка',
    },
  },
  required: ['isPlant', 'species', 'commonName', 'isHealthy', 'healthScore', 'diagnosis', 'treatmentPlan', 'careAdvice'],
};

const SYSTEM_PROMPT = `Ты — опытный ботаник и фитопатолог приложения Sprout AI.
По фотографии растения определи вид, оцени здоровье, диагностируй болезни
(дефициты питания, вредители, грибок, перелив/недолив, ожоги) и составь план ухода.
Отвечай на русском языке, кратко и конкретно. Если на фото нет растения,
верни isPlant=false и заполни остальные поля пустыми значениями.`;

export async function analyzePlantImage(jpegBuffer, { previousDiagnosis = null } = {}) {
  const parts = [
    { inlineData: { mimeType: 'image/jpeg', data: jpegBuffer.toString('base64') } },
    { text: 'Проанализируй растение на фото.' },
  ];
  if (previousDiagnosis) {
    parts.push({
      text: `Предыдущий диагноз этого растения (${previousDiagnosis.scannedAt}): ${previousDiagnosis.title}. ${previousDiagnosis.description}. Оцени динамику в поле progressNote.`,
    });
  }

  const response = await ai.models.generateContent({
    model: config.geminiModel,
    contents: [{ role: 'user', parts }],
    config: {
      systemInstruction: SYSTEM_PROMPT,
      responseMimeType: 'application/json',
      responseSchema,
      temperature: 0.3,
    },
  });

  return JSON.parse(response.text);
}
