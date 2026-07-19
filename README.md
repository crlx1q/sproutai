# Sprout AI 🌱

Карманный эксперт-ботаник: фото растения → вид, болезнь, план лечения и ухода.
Напоминания о поливе, дневник «до/после», комьюнити и Pro-подписка.

## Состав проекта

| Папка | Что это |
|---|---|
| `server/` | Node.js (Express) API + лендинг + админ-панель `/admin` |
| `app/` | Flutter-приложение (Android / iOS) |
| `DESIGN.md`, `1-4.png` | Дизайн-система «Botanical Modern» и референсы экранов |

## Быстрый старт

### Сервер

```bash
cd server
npm install
npm start          # http://localhost:3000
```

Конфигурация лежит в `server/.env` (MongoDB Atlas, ключ Gemini, JWT-секреты,
логин админа). Лендинг — `http://localhost:3000/`, админка — `http://localhost:3000/admin`
(вход: `admin@sproutai.app`, пароль из `.env`).

### Мобильное приложение

```bash
cd app
flutter pub get
flutter run                                    # эмулятор Android (API на 10.0.2.2:3000)
flutter run --dart-define=API_URL=http://192.168.1.10:3000   # реальное устройство
flutter build apk --release                    # сборка APK
```

Собранный APK можно положить в `server/public/app/sprout-ai.apk` — кнопка
«Скачать APK» на лендинге ведёт по этому пути.

## Как устроено

- **ИИ-диагностика** — фото уходит на сервер, сжимается (sharp) и передаётся
  в Gemini со структурированной JSON-схемой: вид, здоровье 0–100, диагноз,
  план лечения, советы по уходу. Ответ кэшируется в коллекции `scans`.
- **Лимиты** — free-план: 5 сканов / 30 дней (проверка на сервере),
  Pro — безлимит. Pro выдаётся через админ-панель (оплата — следующий этап).
- **Повторный скан растения** получает предыдущий диагноз в контекст,
  и Gemini оценивает динамику лечения (`progressNote`).
- **Напоминания** — расписания хранятся на сервере, приложение пересобирает
  локальные уведомления при каждой синхронизации списка растений.
- **Комьюнити** — посты с фото, лайки, комментарии; модерация в админке.

## API (кратко)

- `POST /api/auth/register | login | refresh`, `GET /api/auth/me`
- `GET/POST /api/plants`, `POST /api/plants/:id/water`, `POST /api/plants/water-all`
- `POST /api/plants/:id/journal` — дневник «до/после»
- `GET/POST /api/plants/:id/reminders`
- `POST /api/scan` (multipart `image`), `GET /api/scan/quota`
- `GET/POST /api/community/posts`, `POST .../like`, `GET/POST .../comments`
- `/api/admin/*` — статистика, пользователи, выдача Pro, модерация
