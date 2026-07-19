import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Экран загрузки при старте: показывается, пока идёт восстановление сессии,
/// чтобы вместо обучения (онбординга) пользователь видел заставку.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
