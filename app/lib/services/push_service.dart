import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/api.dart';
import 'notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Фоновые уведомления показывает система; тело обработчика не требуется.
}

/// Пуш-уведомления от сервера через Firebase Cloud Messaging.
///
/// Важно: НЕ обращаемся к FirebaseMessaging.instance в инициализаторах полей —
/// это выполнилось бы до Firebase.initializeApp() и роняло бы синглтон.
class PushService {
  PushService._();
  static final instance = PushService._();

  FirebaseMessaging? _messaging;
  bool _ready = false;
  String? _token;

  bool get isReady => _ready;

  /// Инициализация Firebase. Полностью безопасна: при отсутствии конфига или
  /// Google Play Services приложение продолжает работать без пушей.
  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      await _messaging!
          .requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen(_showForeground);
      _token = await _messaging!.getToken();
      _ready = true;
    } catch (_) {
      // Firebase недоступен — тихо работаем без уведомлений.
      _ready = false;
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await NotificationService.instance.showNow(
      id: n.hashCode,
      title: n.title,
      body: n.body,
    );
  }

  /// Регистрирует токен устройства на сервере (вызывается после входа).
  /// Никогда не бросает исключения наружу.
  Future<void> registerToken(ApiClient api) async {
    if (!_ready) return;
    try {
      _token ??= await _messaging?.getToken();
      if (_token == null) return;
      await api.dio.post('/api/notifications/token', data: {'token': _token});
      _messaging?.onTokenRefresh.listen((t) async {
        _token = t;
        try {
          await api.dio.post('/api/notifications/token', data: {'token': t});
        } catch (_) {}
      });
    } catch (_) {
      // Уведомления не критичны — молча пропускаем ошибки.
    }
  }

  /// Удаляет токен на сервере (при выходе из аккаунта).
  Future<void> unregisterToken(ApiClient api) async {
    if (!_ready || _token == null) return;
    try {
      await api.dio.delete('/api/notifications/token', data: {'token': _token});
    } catch (_) {}
  }
}
