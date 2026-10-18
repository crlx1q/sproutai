import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

/// Экран загрузки при старте: показывается, пока идёт восстановление сессии,
/// чтобы вместо обучения (онбординга) пользователь видел заставку.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/logo.png', width: 96, height: 96),
            ),
            const SizedBox(height: 20),
            Text('Sprout AI', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 28),
            if (auth is AuthRestoreFailed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(auth.message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(authProvider.notifier).retryRestore(),
                      child: const Text('Повторить подключение'),
                    ),
                    TextButton(
                      onPressed: () => ref.read(authProvider.notifier).logout(),
                      child: const Text('Войти другим аккаунтом'),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
