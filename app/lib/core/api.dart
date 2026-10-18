import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  Future<void> _pendingWrites = Future.value();

  /// Refresh, login and logout share a queue. A late write from an older
  /// session completes before the newer session's save/clear can run.
  Future<bool> mutateIfCurrent(
    bool Function() isCurrent,
    Future<void> Function() change,
  ) {
    final next = _pendingWrites.then((_) async {
      if (!isCurrent()) return false;
      await change();
      return isCurrent();
    });
    _pendingWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

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
  ApiClient(this._tokens, {Dio? client, Dio? refreshClient}) {
    dio =
        client ??
        Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
    _refreshDio =
        refreshClient ??
        Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final revision =
              options.extra['sessionRevision'] as int? ?? _sessionRevision;
          options.extra['sessionRevision'] = revision;
          if (_isPublicAuth(options.path)) return handler.next(options);
          String? token;
          try {
            token = await _tokens.accessToken;
          } catch (error) {
            return handler.reject(
              DioException(requestOptions: options, error: error),
            );
          }
          if (revision != _sessionRevision) {
            return handler.reject(_cancelledSession(options));
          }
          if (token != null && !_isPublicAuth(options.path)) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final revision = error.requestOptions.extra['sessionRevision'];
          if (revision != _sessionRevision) {
            return handler.next(_cancelledSession(error.requestOptions));
          }
          if (error.response?.statusCode == 401 &&
              !_isPublicAuth(error.requestOptions.path) &&
              error.requestOptions.extra['sessionRevision'] ==
                  _sessionRevision &&
              error.requestOptions.extra['retried'] != true) {
            final current = await _tokens.accessToken;
            if (revision != _sessionRevision) {
              return handler.next(_cancelledSession(error.requestOptions));
            }
            final changed =
                current != null &&
                error.requestOptions.headers['Authorization'] !=
                    'Bearer $current';
            final refreshed = changed || await _tryRefresh();
            if (revision != _sessionRevision) {
              return handler.next(_cancelledSession(error.requestOptions));
            }
            if (refreshed) {
              final opts = error.requestOptions..extra['retried'] = true;
              // Multipart streams are consumed by the first request.
              if (opts.data is FormData) {
                opts.data = (opts.data as FormData).clone();
              }
              final token = await _tokens.accessToken;
              if (revision != _sessionRevision) {
                return handler.next(_cancelledSession(error.requestOptions));
              }
              opts.headers['Authorization'] = 'Bearer $token';
              try {
                final response = await dio.fetch(opts);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final TokenStorage _tokens;
  late final Dio dio;
  late final Dio _refreshDio;
  Future<bool>? _refreshing;
  int _sessionRevision = 0;
  void Function()? onSessionExpired;

  DioException _cancelledSession(RequestOptions options) => DioException(
    requestOptions: options,
    type: DioExceptionType.cancel,
    message: 'Аккаунт изменился. Старый запрос отменён.',
  );

  static bool _isPublicAuth(String path) =>
      path.endsWith('/auth/login') ||
      path.endsWith('/auth/register') ||
      path.endsWith('/auth/refresh');

  /// Invalidates refresh work started by a previous account.
  void resetSession() {
    _sessionRevision++;
    _refreshing = null;
  }

  Future<bool> _tryRefresh() async {
    if (_refreshing != null) return _refreshing!;
    final future = _refreshTokens();
    _refreshing = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<bool> _refreshTokens() async {
    final revision = _sessionRevision;
    final refresh = await _tokens.refreshToken;
    if (refresh == null) {
      if (revision == _sessionRevision) onSessionExpired?.call();
      return false;
    }
    try {
      final res = await _refreshDio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refresh},
      );
      if (revision != _sessionRevision) return false;
      return await _tokens.mutateIfCurrent(
        () => revision == _sessionRevision,
        () => _tokens.save(res.data['accessToken'], res.data['refreshToken']),
      );
    } on DioException catch (error) {
      if (revision == _sessionRevision &&
          [400, 401, 403].contains(error.response?.statusCode)) {
        final current = await _tokens.mutateIfCurrent(
          () => revision == _sessionRevision,
          _tokens.clear,
        );
        if (current && revision == _sessionRevision) onSessionExpired?.call();
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Человекочитаемое сообщение из ошибки Dio.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (error.response?.statusCode == 402) {
      return 'Лимит ИИ-проверок исчерпан. Можно вести заметки и отмечать уход.';
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'Сервер отвечает дольше обычного. Обновите данные перед повторной отправкой.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Нет соединения с сервером';
    }
  }
  return 'Что-то пошло не так, попробуйте ещё раз';
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(tokenStorageProvider)),
);
