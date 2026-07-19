import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/plants_provider.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final plantsAsync = ref.watch(plantsProvider);
    final userName = auth is AuthLoggedIn ? auth.user.name : '';

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: () => context.push('/add-plant'),
        child: const Icon(Icons.add, size: 28),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref.read(plantsProvider.notifier).reload(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Привет, $userName! 👋',
                          style: theme.textTheme.displayLarge?.copyWith(fontSize: 32)),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle(plantsAsync.value),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      _TasksCard(plants: plantsAsync.value ?? const []),
                      const SizedBox(height: 30),
                      SectionHeader(
                        title: 'Мои джунгли',
                        action: plantsAsync.value?.isNotEmpty == true
                            ? '${plantsAsync.value!.length} раст.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              plantsAsync.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary)),
                ),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(apiErrorMessage(e), textAlign: TextAlign.center),
                    ),
                  ),
                ),
                data: (plants) => plants.isEmpty
                    ? const SliverToBoxAdapter(child: _EmptyJungle())
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.72,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _PlantCard(plant: plants[i]),
                            childCount: plants.length,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(List<Plant>? plants) {
    if (plants == null || plants.isEmpty) {
      return 'Добавьте первое растение — начнём заботиться.';
    }
    final thirsty = plants.where((p) => p.needsWater).length;
    return thirsty == 0
        ? 'Твои джунгли выглядят отлично сегодня.'
        : 'Пара зелёных друзей ждёт внимания.';
  }
}

class _TasksCard extends ConsumerWidget {
  const _TasksCard({required this.plants});

  final List<Plant> plants;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thirsty = plants.where((p) => p.needsWater).toList();
    final theme = Theme.of(context);

    return SoftCard(
      color: AppColors.secondaryContainer,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle),
            child: Icon(
              thirsty.isEmpty ? Icons.check : Icons.water_drop_outlined,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ЗАДАЧИ НА СЕГОДНЯ',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  thirsty.isEmpty
                      ? 'Все политы!'
                      : '${thirsty.length} ${_plural(thirsty.length)}',
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 21),
                ),
                if (thirsty.isNotEmpty)
                  Text('нуждаются в поливе', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          if (thirsty.isNotEmpty)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: () async {
                final n = await ref.read(plantsProvider.notifier).waterAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Полито растений: $n 💧')),
                  );
                }
              },
              child: const Text('Полить все'),
            ),
        ],
      ),
    );
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'растение';
    if ([2, 3, 4].contains(n % 10) && ![12, 13, 14].contains(n % 100)) {
      return 'растения';
    }
    return 'растений';
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: () => context.push('/plant/${plant.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: PlantImage(url: plant.photoUrl, radius: 16, width: double.infinity),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: StatusChip(status: plant.needsWater ? 'needs_attention' : plant.healthStatus),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            plant.name,
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (plant.species.isNotEmpty)
            Text(
              plant.species,
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: plant.needsWater
                  ? AppColors.terracottaContainer
                  : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  size: 13,
                  color: plant.needsWater ? AppColors.terracotta : AppColors.outline,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _wateredLabel(plant.lastWateredAt),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: plant.needsWater ? AppColors.terracotta : AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _wateredLabel(DateTime? d) {
    if (d == null) return 'Полив: неизвестно';
    final days = DateTime.now().difference(d).inDays;
    if (days == 0) return 'Полит: сегодня';
    if (days == 1) return 'Полит: вчера';
    return 'Полит: ${DateFormat('d MMM', 'ru').format(d)}';
  }
}

class _EmptyJungle extends StatelessWidget {
  const _EmptyJungle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 120),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: AppColors.mintSoft, shape: BoxShape.circle),
            child: const Icon(Icons.local_florist_outlined,
                size: 54, color: AppColors.secondary),
          ),
          const SizedBox(height: 24),
          Text('Джунгли пока пусты', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            'Добавьте первое растение вручную или отсканируйте его камерой — Sprout AI сам определит вид.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
