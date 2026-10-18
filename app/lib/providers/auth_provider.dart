import 'dart:async';

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

class AuthRestoreFailed extends AuthState {
  const AuthRestoreFailed(this.message);
  final String message;
}

class AuthLoggedIn extends AuthState {
  const AuthLoggedIn(this.user);
  final User user;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final api = _api;
    api.onSessionExpired = _sessionExpired;
    ref.onDispose(() => api.onSessionExpired = null);
    _restore();
    return const AuthLoading();
  }

  ApiClient get _api => ref.read(apiProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);
  int _operation = 0;

  void _sessionExpired() {
    if (!ref.mounted || state is AuthLoggedOut) return;
    _operation++;
    _api.resetSession();
    state = const AuthLoggedOut();
    unawaited(PushService.instance.clearSession());
  }

  Future<void> _restore() async {
    final operation = _operation;
    try {
      final token = await _tokens.accessToken;
      if (!ref.mounted || operation != _operation) return;
      if (token == null) {
        state = const AuthLoggedOut();
        await PushService.instance.clearSession();
        return;
      }
      final res = await _api.dio.get('/api/auth/me');
      if (!ref.mounted || operation != _operation) return;
      state = AuthLoggedIn(User.fromJson(res.data['user']));
      _registerPush();
    } catch (error) {
      if (!ref.mounted || operation != _operation) return;
      state = AuthRestoreFailed(apiErrorMessage(error));
    }
  }

  void retryRestore() {
    _operation++;
    state = const AuthLoading();
    unawaited(_restore());
  }

  Future<void> login(String email, String password) async {
    final operation = ++_operation;
    _api.resetSession();
    final res = await _api.dio.post(
      '/api/auth/login',
      data: {'email': email, 'password': password},
    );
    if (!ref.mounted || operation != _operation) return;
    await _tokens.mutateIfCurrent(
      () => ref.mounted && operation == _operation,
      () => _tokens.save(res.data['accessToken'], res.data['refreshToken']),
    );
    if (!ref.mounted || operation != _operation) return;
    state = AuthLoggedIn(User.fromJson(res.data['user']));
    _registerPush();
  }

  Future<void> register(String name, String email, String password) async {
    final operation = ++_operation;
    _api.resetSession();
    final res = await _api.dio.post(
      '/api/auth/register',
      data: {'name': name, 'email': email, 'password': password},
    );
    if (!ref.mounted || operation != _operation) return;
    await _tokens.mutateIfCurrent(
      () => ref.mounted && operation == _operation,
      () => _tokens.save(res.data['accessToken'], res.data['refreshToken']),
    );
    if (!ref.mounted || operation != _operation) return;
    state = AuthLoggedIn(User.fromJson(res.data['user']));
    _registerPush();
  }

  Future<void> refreshMe() async {
    final operation = _operation;
    try {
      final res = await _api.dio.get('/api/auth/me');
      if (!ref.mounted || operation != _operation) return;
      state = AuthLoggedIn(User.fromJson(res.data['user']));
      _registerPush();
    } catch (_) {}
  }

  void _registerPush() {
    // Пуши не критичны для входа: любые ошибки инициализации гасим здесь,
    // чтобы они не всплывали как «Что-то пошло не так» на экране входа.
    try {
      unawaited(PushService.instance.registerToken(_api));
    } catch (_) {}
  }

  Future<void> logout() async {
    if (state is AuthLoading || state is AuthLoggedOut) return;
    final wasLoggedIn = state is AuthLoggedIn;
    final operation = ++_operation;
    _api.resetSession();
    state = const AuthLoading();
    try {
      if (wasLoggedIn) {
        await PushService.instance.unregisterToken(_api);
      } else {
        await PushService.instance.clearSession();
      }
    } catch (_) {}
    if (!ref.mounted || operation != _operation) return;
    await _tokens.mutateIfCurrent(
      () => ref.mounted && operation == _operation,
      _tokens.clear,
    );
    if (!ref.mounted || operation != _operation) return;
    state = const AuthLoggedOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
