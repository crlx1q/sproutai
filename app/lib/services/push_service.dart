import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../models/models.dart';
import 'notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Notification payloads are displayed by the operating system.
}

/// A Firebase token alone does not prove the server knows this device.
bool shouldUseServerReminders({
  required bool firebaseReady,
  required bool hasPermission,
  required String? token,
  required String? registeredToken,
  required bool? serverPushEnabled,
}) =>
    firebaseReady &&
    hasPermission &&
    token != null &&
    registeredToken == token &&
    serverPushEnabled == true;

class PushService {
  PushService._();
  static final instance = PushService._();

  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  Future<void>? _initializing;
  Future<void>? _registration;
  ApiClient? _api;
  bool _ready = false;
  bool _hasPermission = false;
  bool? _serverPushEnabled;
  String? _token;
  String? _registeredToken;
  List<Plant> _plants = const [];
  int _sessionRevision = 0;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    var work = _initializing;
    if (work == null) {
      late final Future<void> startup;
      startup = _initialize().whenComplete(() {
        if (identical(_initializing, startup)) _initializing = null;
        final api = _api;
        if (_ready && api != null) {
          unawaited(_registerAfterInitialization(api, _sessionRevision));
        }
      });
      _initializing = startup;
      work = startup;
    }
    try {
      // Keep one native initialization in flight, but let the signed-in app
      // use local reminders if Firebase takes too long to become available.
      await work.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint(
        '[push] Firebase initialization deferred; using local reminders',
      );
    }
  }

  Future<void> _registerAfterInitialization(ApiClient api, int revision) async {
    await _registration;
    if (_isCurrent(api, revision) &&
        (_token == null || _registeredToken != _token)) {
      await registerToken(api);
    }
  }

  Future<void> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      _foreground ??= FirebaseMessaging.onMessage.listen(_showForeground);
      _opened ??= FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      final initial = await _messaging!.getInitialMessage();
      if (initial != null) _openMessage(initial);
      _ready = true;
    } catch (error) {
      debugPrint('[push] Firebase unavailable: ${error.runtimeType}');
      _ready = false;
    }
  }

  void _openMessage(RemoteMessage message) {
    NotificationService.instance.openPlant(message.data['plantId'] as String?);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    if (_api == null) return;
    final notification = message.notification;
    if (notification == null) return;
    await NotificationService.instance.showNow(
      id: (message.messageId ?? message.data.toString()).hashCode,
      title: notification.title,
      body: notification.body,
      plantId: message.data['plantId'] as String?,
    );
  }

  /// One current session and one token listener. Retries also run on app resume.
  Future<void> registerToken(ApiClient api) async {
    _api = api;
    final revision = _sessionRevision;
    if (_registration != null) return _registration;
    final work = _register(api, revision);
    _registration = work;
    try {
      await work;
    } finally {
      if (identical(_registration, work)) _registration = null;
    }
  }

  bool _isCurrent(ApiClient api, int revision) =>
      identical(_api, api) && revision == _sessionRevision;

  Future<void> _register(ApiClient api, int revision) async {
    try {
      await init();
      if (!_isCurrent(api, revision)) return;
      if (!_ready) {
        _hasPermission = await NotificationService.instance.requestPermission();
        if (_isCurrent(api, revision)) await _applyDeliveryMode();
        return;
      }
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!_isCurrent(api, revision)) return;
      _hasPermission =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!_hasPermission) {
        await NotificationService.instance.cancelReminders();
        return;
      }
      _tokenRefresh ??= _messaging!.onTokenRefresh.listen((token) {
        _token = token;
        final activeApi = _api;
        final activeRevision = _sessionRevision;
        if (activeApi != null) {
          unawaited(() async {
            await _registration;
            if (_isCurrent(activeApi, activeRevision) &&
                _registeredToken != token) {
              await registerToken(activeApi);
            }
          }());
        }
      });
      _token = await _messaging!.getToken().timeout(
        const Duration(seconds: 20),
      );
      if (!_isCurrent(api, revision)) return;
      if (_token == null) {
        await _applyDeliveryMode();
        return;
      }
      final registered = _token!;
      final response = await api.dio.post(
        '/api/notifications/token',
        data: {'token': registered},
      );
      if (!_isCurrent(api, revision)) return;
      _registeredToken = registered;
      _serverPushEnabled = response.data['pushEnabled'] == true;
      await _applyDeliveryMode();
    } catch (error) {
      debugPrint('[push] Device registration deferred: ${error.runtimeType}');
      if (_isCurrent(api, revision)) await _applyDeliveryMode();
    }
  }

  Future<void> syncReminders(List<Plant> plants) async {
    if (_api == null) return;
    _plants = List.unmodifiable(plants);
    await _applyDeliveryMode();
  }

  Future<void> _applyDeliveryMode() async {
    if (_api == null) return;
    if (!_hasPermission) {
      await NotificationService.instance.cancelReminders();
      return;
    }
    // Retain a previously confirmed registration during transient failures.
    // First-registration failures and rotated, unregistered tokens use locals.
    final remote = shouldUseServerReminders(
      firebaseReady: _ready,
      hasPermission: _hasPermission,
      token: _token,
      registeredToken: _registeredToken,
      serverPushEnabled: _serverPushEnabled,
    );
    if (remote) {
      await NotificationService.instance.cancelReminders();
    } else {
      await NotificationService.instance.syncWateringReminders(_plants);
    }
  }

  Future<void> refresh() async {
    final api = _api;
    if (api != null) await registerToken(api);
  }

  /// Local-only cleanup, also safe when an expired session cannot contact the server.
  Future<void> clearSession() async {
    _sessionRevision++;
    _api = null;
    _plants = const [];
    _registeredToken = null;
    _serverPushEnabled = null;
    _hasPermission = false;
    _registration = null;
    final tokenRefresh = _tokenRefresh;
    _tokenRefresh = null;
    await tokenRefresh?.cancel();
    await NotificationService.instance.cancelAll();
  }

  Future<void> unregisterToken(ApiClient api) async {
    final pending = _registration;
    final tokens = {_token, _registeredToken}..remove(null);
    await clearSession();
    // Let a registration already in flight finish before deleting its token.
    try {
      await pending?.timeout(const Duration(seconds: 3));
    } catch (_) {}
    for (final token in tokens) {
      try {
        await api.dio.delete(
          '/api/notifications/token',
          data: {'token': token},
        );
      } catch (error) {
        debugPrint('[push] Device unregister deferred: ${error.runtimeType}');
      }
    }
  }
}
