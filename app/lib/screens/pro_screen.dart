import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../widgets/common.dart';

class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  String _plan = 'yearly';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.primaryContainer,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.pop(),
            ),
            title: const Text(
              'Sprout Pro',
              style: TextStyle(color: Colors.white),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryContainer, AppColors.primary],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Забота о каждом растении',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Больше возможностей для диагностики вашего сада',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.primaryFixedDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Benefit(
                    icon: Icons.all_inclusive,
                    color: AppColors.secondaryContainer,
                    title: 'БЕЗЛИМИТ',
                    text: 'Неограниченная ИИ-диагностика ваших растений.',
                  ),
                  const _Benefit(
                    icon: Icons.forum_outlined,
                    color: AppColors.mintSoft,
                    title: 'НАБЛЮДЕНИЯ',
                    text: 'Регулярно проверяйте состояние растений по фото.',
                  ),
                  const _Benefit(
                    icon: Icons.trending_up,
                    color: AppColors.terracottaContainer,
                    title: 'ТРЕКИНГ РОСТА',
                    text:
                        'Фото по неделям и история развития доступны в карточке растения.',
                  ),
                  const _Benefit(
                    icon: Icons.block,
                    color: AppColors.surfaceContainer,
                    title: 'БЕЗ РЕКЛАМЫ',
                    text: 'Ничто не отвлекает от ухода за растениями.',
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Планы после запуска оплаты',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _PlanTile(
                    selected: _plan == 'yearly',
                    title: 'Годовой',
                    price: '\$24.99 / год',
                    trailing: '~\$2.08/мес',
                    badge: 'ЭКОНОМИЯ 30%',
                    onTap: () => setState(() => _plan = 'yearly'),
                  ),
                  const SizedBox(height: 12),
                  _PlanTile(
                    selected: _plan == 'monthly',
                    title: 'Месячный',
                    price: '\$2.99 / мес',
                    onTap: () => setState(() => _plan = 'monthly'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: theme.colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          title: const Text('Оплата скоро!'),
                          content: const Text(
                            'Внутренние покупки в разработке. Напишите нам на hello@sproutai.app — включим Pro вручную.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Понятно'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Как подключить Pro'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Оплата в приложении пока недоступна. Пробный период и автоматическое продление ещё не запущены.',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: 21, color: AppColors.primaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(text, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.selected,
    required this.title,
    required this.price,
    this.trailing,
    this.badge,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String price;
  final String? trailing;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: softShadow(),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              badge!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(price, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailing!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
