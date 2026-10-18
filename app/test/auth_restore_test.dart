import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprout_ai/core/api.dart';
import 'package:sprout_ai/providers/auth_provider.dart';

class _Tokens extends TokenStorage {
  String? access = 'saved-access';
  String? refresh = 'saved-refresh';
  @override
  Future<String?> get accessToken async => access;
  @override
  Future<String?> get refreshToken async => refresh;
  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class _FailureAdapter implements HttpClientAdapter {
  _FailureAdapter({required this.unauthorized, this.onRequest});
  final bool unauthorized;
  final void Function()? onRequest;
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    onRequest?.call();
    if (!unauthorized) {
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      '{}',
      401,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<AuthState> _restored(ProviderContainer container) async {
  final done = Completer<AuthState>();
  final subscription = container.listen(authProvider, (_, state) {
    if (state is! AuthLoading && !done.isCompleted) done.complete(state);
  }, fireImmediately: true);
  try {
    return await done.future.timeout(const Duration(seconds: 3));
  } finally {
    subscription.close();
  }
}

void main() {
  test(
    'offline startup preserves credentials and allows restoring without a new login',
    () async {
      final tokens = _Tokens();
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://local.test'))
        ..httpClientAdapter = _FailureAdapter(
          unauthorized: false,
          onRequest: () => calls++,
        );
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokens),
          apiProvider.overrideWithValue(ApiClient(tokens, client: dio)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authProvider, (_, _) {});
      expect(await _restored(container), isA<AuthRestoreFailed>());
      expect(tokens.refresh, 'saved-refresh');
      container.read(authProvider.notifier).retryRestore();
      await _restored(container);
      expect(calls, 2);
      expect(container.read(authProvider), isA<AuthRestoreFailed>());
    },
  );

  test(
    'expired saved refresh token redirects to login rather than an endless retry',
    () async {
      final tokens = _Tokens();
      Dio unauthorized() =>
          Dio(BaseOptions(baseUrl: 'https://local.test'))
            ..httpClientAdapter = _FailureAdapter(unauthorized: true);
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokens),
          apiProvider.overrideWithValue(
            ApiClient(
              tokens,
              client: unauthorized(),
              refreshClient: unauthorized(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authProvider, (_, _) {});
      expect(await _restored(container), isA<AuthLoggedOut>());
      expect(tokens.refresh, isNull);
    },
  );
}
