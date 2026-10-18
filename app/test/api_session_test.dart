import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprout_ai/core/api.dart';

class MemoryTokens extends TokenStorage {
  String? access = 'expired';
  String? refresh = 'refresh-old';
  @override
  Future<String?> get accessToken async => access;
  @override
  Future<String?> get refreshToken async => refresh;
  @override
  Future<void> save(String access, String refresh) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    await stream?.drain<void>();
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class DelayedTokens extends MemoryTokens {
  final saveStarted = Completer<void>();
  final releaseSave = Completer<void>();
  @override
  Future<void> save(String access, String refresh) async {
    if (access == 'late-old-account') {
      saveStarted.complete();
      await releaseSave.future;
    }
    await super.save(access, refresh);
  }
}

class DelayedReadTokens extends MemoryTokens {
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool _first = true;
  @override
  Future<String?> get accessToken async {
    if (_first) {
      _first = false;
      readStarted.complete();
      await releaseRead.future;
    }
    return access;
  }
}

ResponseBody jsonResponse(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

Dio stub(Future<ResponseBody> Function(RequestOptions) respond) =>
    Dio(BaseOptions(baseUrl: 'https://local.test'))
      ..httpClientAdapter = StubAdapter(respond);

void main() {
  test(
    'request waiting for secure storage is cancelled after account switch',
    () async {
      final tokens = DelayedReadTokens();
      var sent = 0;
      final api = ApiClient(
        tokens,
        client: stub((_) async {
          sent++;
          return jsonResponse(200, {});
        }),
      );
      final pending = expectLater(
        api.dio.post('/api/community/posts', data: {'text': 'Old draft'}),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'cancelled',
            DioExceptionType.cancel,
          ),
        ),
      );
      await tokens.readStarted.future;
      api.resetSession();
      await tokens.mutateIfCurrent(
        () => true,
        () => tokens.save('new-account', 'new-refresh'),
      );
      tokens.releaseRead.complete();
      await pending;
      expect(sent, 0);
    },
  );

  test('slow old refresh storage write cannot overwrite newer login', () async {
    final tokens = DelayedTokens();
    final api = ApiClient(
      tokens,
      client: stub((_) async => jsonResponse(401, {})),
      refreshClient: stub(
        (_) async => jsonResponse(200, {
          'accessToken': 'late-old-account',
          'refreshToken': 'late-old-refresh',
        }),
      ),
    );
    final pending = expectLater(
      api.dio.get('/api/plants'),
      throwsA(isA<DioException>()),
    );
    await tokens.saveStarted.future;
    api.resetSession();
    final newLogin = tokens.mutateIfCurrent(
      () => true,
      () => tokens.save('new-account', 'new-refresh'),
    );
    tokens.releaseSave.complete();
    await Future.wait([pending, newLogin]);
    expect(tokens.access, 'new-account');
    expect(tokens.refresh, 'new-refresh');
  });
  test('parallel expired requests share one token refresh', () async {
    final tokens = MemoryTokens();
    var refreshCalls = 0;
    final api = ApiClient(
      tokens,
      client: stub(
        (request) async => jsonResponse(
          request.headers['Authorization'] == 'Bearer fresh' ? 200 : 401,
          {'ok': true},
        ),
      ),
      refreshClient: stub((_) async {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonResponse(200, {
          'accessToken': 'fresh',
          'refreshToken': 'refresh-new',
        });
      }),
    );
    final responses = await Future.wait([
      api.dio.get('/api/plants'),
      api.dio.get('/api/community/posts'),
    ]);
    expect(responses.every((response) => response.statusCode == 200), isTrue);
    expect(refreshCalls, 1);
  });

  test('multipart image is replayable after access token expiry', () async {
    final tokens = MemoryTokens();
    var attempts = 0;
    final api = ApiClient(
      tokens,
      client: stub((request) async {
        attempts++;
        return jsonResponse(attempts == 1 ? 401 : 200, {'ok': true});
      }),
      refreshClient: stub(
        (_) async =>
            jsonResponse(200, {'accessToken': 'fresh', 'refreshToken': 'new'}),
      ),
    );
    final result = await api.dio.post(
      '/api/scan',
      data: FormData.fromMap({
        'image': MultipartFile.fromBytes([1, 2, 3], filename: 'plant.jpg'),
      }),
    );
    expect(result.statusCode, 200);
    expect(attempts, 2);
  });

  test('temporary refresh outage does not destroy login', () async {
    final tokens = MemoryTokens();
    var expired = false;
    final api = ApiClient(
      tokens,
      client: stub((_) async => jsonResponse(401, {})),
      refreshClient: stub(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      ),
    );
    api.onSessionExpired = () => expired = true;
    await expectLater(api.dio.get('/api/plants'), throwsA(isA<DioException>()));
    expect(tokens.refresh, 'refresh-old');
    expect(expired, isFalse);
  });

  test('rejected refresh expires the app session', () async {
    final tokens = MemoryTokens();
    var expired = false;
    final api = ApiClient(
      tokens,
      client: stub((_) async => jsonResponse(401, {})),
      refreshClient: stub((_) async => jsonResponse(401, {})),
    );
    api.onSessionExpired = () => expired = true;
    await expectLater(api.dio.get('/api/plants'), throwsA(isA<DioException>()));
    expect(tokens.access, isNull);
    expect(expired, isTrue);
  });

  test('incorrect login does not attempt a refresh', () async {
    final tokens = MemoryTokens();
    var refreshCalls = 0;
    final api = ApiClient(
      tokens,
      client: stub((_) async => jsonResponse(401, {})),
      refreshClient: stub((_) async {
        refreshCalls++;
        return jsonResponse(401, {});
      }),
    );
    await expectLater(
      api.dio.post('/api/auth/login'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCalls, 0);
    expect(tokens.refresh, isNotNull);
  });

  test(
    'refresh in flight cannot restore an old account after logout',
    () async {
      final tokens = MemoryTokens();
      final started = Completer<void>();
      final release = Completer<void>();
      final api = ApiClient(
        tokens,
        client: stub((_) async => jsonResponse(401, {})),
        refreshClient: stub((_) async {
          started.complete();
          await release.future;
          return jsonResponse(200, {
            'accessToken': 'old-account',
            'refreshToken': 'old-refresh',
          });
        }),
      );
      final pending = expectLater(
        api.dio.get('/api/plants'),
        throwsA(isA<DioException>()),
      );
      await started.future;
      api.resetSession();
      await tokens.clear();
      release.complete();
      await pending;
      expect(tokens.access, isNull);
    },
  );
}
