import 'package:flutter/foundation.dart';

/// Базовый адрес API.
///
/// По умолчанию — адрес хоста из Android-эмулятора (10.0.2.2 = localhost ПК).
/// Для реального устройства укажите IP компьютера или прод-домен:
/// flutter run --dart-define=API_URL=http://192.168.1.10:3000
class ApiConfig {
  static const String _override = String.fromEnvironment('API_URL');

  /// В debug-сборке (flutter run) по умолчанию — локальный сервер эмулятора
  /// (10.0.2.2 = localhost ПК). В release-сборке — боевой домен.
  /// Переопределить в любой сборке: --dart-define=API_URL=https://...
  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    return kReleaseMode
        ? 'https://sproutai.crlx1q.com'
        : 'http://10.0.2.2:3000';
  }

  static String imageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
