import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/push_service.dart';

sealed class AuthState {
  const AuthState();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthLoggedOut extends AuthState {
  const AuthLoggedOut();
}

class AuthLoggedIn extends AuthState {
  const AuthLoggedIn(this.user);
  final User user;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthLoading();
  }

  ApiClient get _api => ref.read(apiProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  Future<void> _restore() async {
    final token = await _tokens.accessToken;
    if (token == null) {
      state = const AuthLoggedOut();
      return;
    }
    try {
      final res = await _api.dio.get('/api/auth/me');
      state = AuthLoggedIn(User.fromJson(res.data['user']));
      _registerPush();
    } catch (_) {
      state = const AuthLoggedOut();
    }
  }

  Future<void> login(String email, String password) async {
    final res = await _api.dio.post('/api/auth/login',
        data: {'email': email, 'password': password});
    await _tokens.save(res.data['accessToken'], res.data['refreshToken']);
    state = AuthLoggedIn(User.fromJson(res.data['user']));
    _registerPush();
  }

  Future<void> register(String name, String email, String password) async {
    final res = await _api.dio.post('/api/auth/register',
        data: {'name': name, 'email': email, 'password': password});
    await _tokens.save(res.data['accessToken'], res.data['refreshToken']);
    state = AuthLoggedIn(User.fromJson(res.data['user']));
    _registerPush();
  }

  Future<void> refreshMe() async {
    try {
      final res = await _api.dio.get('/api/auth/me');
      state = AuthLoggedIn(User.fromJson(res.data['user']));
    } catch (_) {}
  }

  void _registerPush() {
    // Пуши не критичны для входа: любые ошибки инициализации гасим здесь,
    // чтобы они не всплывали как «Что-то пошло не так» на экране входа.
    try {
      PushService.instance.registerToken(_api);
    } catch (_) {}
  }

  Future<void> logout() async {
    try {
      await PushService.instance.unregisterToken(_api);
    } catch (_) {}
    await _tokens.clear();
    state = const AuthLoggedOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
