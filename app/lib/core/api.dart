import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();

  Future<String?> get accessToken => _storage.read(key: 'accessToken');
  Future<String?> get refreshToken => _storage.read(key: 'refreshToken');

  Future<void> save(String access, String refresh) async {
    await _storage.write(key: 'accessToken', value: access);
    await _storage.write(key: 'refreshToken', value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: 'accessToken');
    await _storage.delete(key: 'refreshToken');
  }
}

class ApiClient {
  ApiClient(this._tokens) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokens.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['retried'] != true) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final opts = error.requestOptions..extra['retried'] = true;
            final token = await _tokens.accessToken;
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await dio.fetch(opts);
              return handler.resolve(response);
            } catch (_) {}
          }
        }
        handler.next(error);
      },
    ));
  }

  final TokenStorage _tokens;
  late final Dio dio;

  Future<bool> _tryRefresh() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          .post('/api/auth/refresh', data: {'refreshToken': refresh});
      await _tokens.save(res.data['accessToken'], res.data['refreshToken']);
      return true;
    } catch (_) {
      await _tokens.clear();
      return false;
    }
  }
}

/// Человекочитаемое сообщение из ошибки Dio.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Нет соединения с сервером';
    }
  }
  return 'Что-то пошло не так, попробуйте ещё раз';
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
final apiProvider =
    Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStorageProvider)));
