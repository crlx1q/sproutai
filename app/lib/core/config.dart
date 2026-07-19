/// Базовый адрес API.
///
/// По умолчанию — адрес хоста из Android-эмулятора (10.0.2.2 = localhost ПК).
/// Для реального устройства укажите IP компьютера или прод-домен:
/// flutter run --dart-define=API_URL=http://192.168.1.10:3000
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://sproutai.crlx1q.com',
  );

  static String imageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
