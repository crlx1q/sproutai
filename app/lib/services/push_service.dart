import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/api.dart';
import 'notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Фоновые уведомления показывает система; тело обработчика не требуется.
}

/// Пуш-уведомления от сервера через Firebase Cloud Messaging.
class PushService {
  PushService._();
  static final instance = PushService._();

  final _messaging = FirebaseMessaging.instance;
  bool _ready = false;
  String? _token;

  Future<void> init() async {
    if (_ready) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Когда приложение открыто — показываем уведомление вручную.
    FirebaseMessaging.onMessage.listen(_showForeground);

    _token = await _messaging.getToken();
    _ready = true;
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
  Future<void> registerToken(ApiClient api) async {
    try {
      _token ??= await _messaging.getToken();
      if (_token == null) return;
      await api.dio.post('/api/notifications/token', data: {'token': _token});
      _messaging.onTokenRefresh.listen((t) async {
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
    try {
      if (_token == null) return;
      await api.dio.delete('/api/notifications/token', data: {'token': _token});
    } catch (_) {}
  }
}
