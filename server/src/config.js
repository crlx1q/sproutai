import 'dotenv/config';

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  mongoUri: process.env.MONGODB_URI,
  geminiApiKey: process.env.GEMINI_API_KEY,
  geminiModel: process.env.GEMINI_MODEL || 'gemini-flash-lite-latest',
  jwtSecret: process.env.JWT_SECRET,
  jwtRefreshSecret: process.env.JWT_REFRESH_SECRET,
  adminEmail: process.env.ADMIN_EMAIL,
  adminPassword: process.env.ADMIN_PASSWORD,
  freeScansPerMonth: parseInt(process.env.FREE_SCANS_PER_MONTH || '5', 10),
  firebaseServiceAccountPath:
    process.env.FIREBASE_SERVICE_ACCOUNT || './firebase-service-account.json',
  accessTokenTtl: '30m',
  refreshTokenTtl: '90d',
};
