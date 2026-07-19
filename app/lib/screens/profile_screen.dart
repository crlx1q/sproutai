import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/plants_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final plants = ref.watch(plantsProvider).value ?? const [];
    final quota = ref.watch(scanQuotaProvider).value;

    if (auth is! AuthLoggedIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final user = auth.user;
    final healthy = plants.where((p) => p.healthStatus == 'thriving').length;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          SoftCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.secondaryContainer,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: theme.textTheme.titleLarge),
                      Text(user.email, style: theme.textTheme.labelSmall),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: user.isPro
                              ? AppColors.secondaryContainer
                              : AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          user.isPro ? '✨ Sprout Pro' : 'Бесплатный план',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: user.isPro
                                ? AppColors.primaryContainer
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                    value: '${plants.length}', label: 'Растений'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(value: '$healthy', label: 'Здоровы'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  value: quota == null
                      ? '—'
                      : quota.isUnlimited
                          ? '∞'
                          : '${quota.remaining}',
                  label: 'Сканов ост.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!user.isPro)
            SoftCard(
              color: AppColors.primary,
              onTap: () => context.push('/pro'),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.secondaryContainer, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Перейти на Pro',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: Colors.white)),
                        Text(
                          'Безлимит диагностик и эксперты 24/7',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: AppColors.primaryFixedDim),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.dark_mode_outlined,
                      size: 22, color: theme.colorScheme.secondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Тёмная тема',
                        style: theme.textTheme.bodyLarge),
                  ),
                  Switch(
                    value: ref.watch(themeModeProvider) == ThemeMode.dark,
                    onChanged: (v) =>
                        ref.read(themeModeProvider.notifier).setDark(v),
                  ),
                ],
              ),
            ),
          ),
          _MenuTile(
            icon: Icons.refresh,
            title: 'Синхронизировать данные',
            subtitle: 'Обновить растения, профиль и лимиты',
            onTap: () async {
              try {
                await ref.read(plantsProvider.notifier).reload();
                await ref.read(authProvider.notifier).refreshMe();
                ref.invalidate(scanQuotaProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Данные обновлены ✅')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(apiErrorMessage(e))),
                  );
                }
              }
            },
          ),
          _MenuTile(
            icon: Icons.logout,
            title: 'Выйти из аккаунта',
            color: AppColors.terracotta,
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Sprout AI v2.0.0',
                style: theme.textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.headlineLarge?.copyWith(fontSize: 26)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? AppColors.secondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: color ?? AppColors.onSurface,
                      )),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.outlineVariant),
          ],
        ),
      ),
    );
  }
}
