import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/plants_provider.dart';
import '../widgets/common.dart';

class PlantScreen extends ConsumerWidget {
  const PlantScreen({super.key, required this.plantId});

  final String plantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(plantDetailsProvider(plantId));

    return Scaffold(
      body: detailsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(apiErrorMessage(e), textAlign: TextAlign.center),
          ),
        ),
        data: (details) => _PlantDetailsView(details: details),
      ),
    );
  }
}

class _PlantDetailsView extends ConsumerWidget {
  const _PlantDetailsView({required this.details});

  final PlantDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plant = details.plant;
    final diagnosis = plant.lastDiagnosis;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          actions: [
            PopupMenuButton<String>(
              color: Colors.white,
              onSelected: (v) async {
                if (v == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      title: const Text('Удалить растение?'),
                      content: const Text(
                          'Журнал и напоминания тоже будут удалены.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Удалить',
                              style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref
                        .read(plantsProvider.notifier)
                        .deletePlant(plant.id);
                    if (context.mounted) context.pop();
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Удалить растение')),
              ],
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            titlePadding:
                const EdgeInsets.symmetric(horizontal: 52, vertical: 14),
            title: Text(
              plant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                PlantImage(url: plant.photoUrl, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xC0012D1D)],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plant.species.isNotEmpty)
                        Text(
                          plant.species,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.primaryFixedDim,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          plant.location == 'indoor' ? 'Комнатное' : 'Уличное',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (plant.isGrown) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '🌱 ${stageLabel(plant.stage)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Кнопки быстрых действий
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await ref
                              .read(plantsProvider.notifier)
                              .water(plant.id);
                          ref.invalidate(plantDetailsProvider(plant.id));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Полив отмечен 💧')),
                            );
                          }
                        },
                        icon: const Icon(Icons.water_drop_outlined, size: 19),
                        label: Text(plant.needsWater ? 'Полить сейчас' : 'Полито'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/scan'),
                        icon: const Icon(Icons.center_focus_weak, size: 19),
                        label: const Text('Скан'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Health score
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('HEALTH SCORE',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(letterSpacing: 1.2)),
                          Text('${plant.healthScore}/100',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: plant.healthScore / 100,
                          minHeight: 10,
                          backgroundColor: AppColors.surfaceContainer,
                          valueColor: AlwaysStoppedAnimation(
                            plant.healthScore >= 70
                                ? AppColors.secondary
                                : plant.healthScore >= 45
                                    ? const Color(0xFFB77B1F)
                                    : AppColors.terracotta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                _CheckupCard(
                  plant: plant,
                  onCheckup: () => _runCheckup(context, ref, plant),
                ),

                // Диагноз ИИ
                if (diagnosis != null) ...[
                  const SizedBox(height: 16),
                  SoftCard(
                    color: diagnosis.isHealthy
                        ? AppColors.mintSoft
                        : AppColors.terracottaContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ДИАГНОЗ ИИ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.2,
                            color: diagnosis.isHealthy
                                ? AppColors.secondary
                                : AppColors.terracotta,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(diagnosis.title,
                            style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(diagnosis.description,
                            style: theme.textTheme.bodyMedium),
                        if (diagnosis.treatmentPlan.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          ...diagnosis.treatmentPlan.asMap().entries.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${e.key + 1}. ',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.w700)),
                                      Expanded(
                                        child: Text(e.value,
                                            style:
                                                theme.textTheme.bodyMedium),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                        if (diagnosis.scannedAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Скан от ${DateFormat('d MMMM', 'ru').format(diagnosis.scannedAt!)}',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                const SectionHeader(title: 'Расписание ухода'),
                const SizedBox(height: 4),
                Text('Когда и сколько поливать — по расчёту ИИ',
                    style: theme.textTheme.labelSmall),
                const SizedBox(height: 12),
                _ScheduleCard(plant: plant),

                const SizedBox(height: 28),
                SectionHeader(
                  title: 'Уход & Баланс',
                  action: 'Изменить',
                  onAction: () => _editCare(context, ref, plant),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
                    _CareTile(
                      icon: Icons.water_drop_outlined,
                      label: 'ПОЛИВ',
                      value: 'Раз в ${plant.care.wateringIntervalDays} дн.',
                      highlight: plant.needsWater,
                    ),
                    _CareTile(
                      icon: Icons.local_drink_outlined,
                      label: 'ПОРЦИЯ ВОДЫ',
                      value: '${plant.care.waterAmountMl} мл',
                    ),
                    _CareTile(
                      icon: Icons.wb_sunny_outlined,
                      label: 'ОСВЕЩЕНИЕ',
                      value: plant.care.light,
                    ),
                    _CareTile(
                      icon: Icons.science_outlined,
                      label: 'УДОБРЕНИЕ',
                      value:
                          'Раз в ${plant.care.fertilizerIntervalDays} дн.',
                    ),
                    _CareTile(
                      icon: Icons.thermostat_outlined,
                      label: 'ТЕМПЕРАТУРА',
                      value: plant.care.temperature,
                    ),
                  ],
                ),

                const SizedBox(height: 28),
                SectionHeader(
                  title: 'История растения (до/после)',
                  action: 'Добавить',
                  onAction: () => _addJournalEntry(context, ref, plant.id),
                ),
                const SizedBox(height: 4),
                Text('Прогресс по месяцам — фото и оценки ИИ',
                    style: theme.textTheme.labelSmall),
                const SizedBox(height: 14),
                if (details.journal.isEmpty)
                  SoftCard(
                    child: Row(
                      children: [
                        const Icon(Icons.photo_camera_outlined,
                            color: AppColors.outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Сделайте первое фото — и следите, как растение меняется со временем.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._buildTimeline(context, details.journal),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runCheckup(
      BuildContext context, WidgetRef ref, Plant plant) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 88);
    if (picked == null) return;

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    try {
      final photo =
          await MultipartFile.fromFile(picked.path, filename: 'checkup.jpg');
      final data =
          await ref.read(plantsProvider.notifier).checkup(plant.id, photo);
      ref.invalidate(plantDetailsProvider(plant.id));
      if (context.mounted) {
        Navigator.of(context).pop(); // убрать лоадер
        final result = (data['result'] as Map?)?.cast<String, dynamic>();
        final advice = (data['growthAdvice'] as List?)?.cast<String>() ?? [];
        await _showCheckupResult(context, result, advice);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _showCheckupResult(BuildContext context,
      Map<String, dynamic>? result, List<String> advice) async {
    final score = (result?['healthScore'] as num?)?.toInt();
    final progress = (result?['progressNote'] ?? '') as String;
    final title =
        ((result?['diagnosis'] as Map?)?['title'] ?? 'Готово') as String;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(score != null ? 'Состояние: $score/100' : 'Готово'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (progress.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(progress),
            ],
            if (advice.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Что сделать:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...advice.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $a'),
                  )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отлично'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline(
      BuildContext context, List<JournalEntry> journal) {
    final widgets = <Widget>[];
    String? currentMonth;
    for (final entry in journal) {
      final month = DateFormat('LLLL yyyy', 'ru').format(entry.createdAt);
      if (month != currentMonth) {
        currentMonth = month;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text(
            month.isNotEmpty
                ? month[0].toUpperCase() + month.substring(1)
                : month,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ));
      }
      widgets.add(_JournalCard(entry: entry));
    }
    return widgets;
  }

  Future<void> _editCare(
      BuildContext context, WidgetRef ref, Plant plant) async {
    var watering = plant.care.wateringIntervalDays;
    var fertilizer = plant.care.fertilizerIntervalDays;
    var waterMl = plant.care.waterAmountMl;
    final lightCtrl = TextEditingController(text: plant.care.light);
    final tempCtrl = TextEditingController(text: plant.care.temperature);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Уход & Баланс',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 20),
              Text('Полив: раз в $watering дн.'),
              Slider(
                value: watering.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                activeColor: AppColors.primary,
                onChanged: (v) => setSheetState(() => watering = v.round()),
              ),
              Text('Порция воды: $waterMl мл'),
              Slider(
                value: waterMl.toDouble().clamp(50, 1000),
                min: 50,
                max: 1000,
                divisions: 19,
                activeColor: AppColors.primary,
                onChanged: (v) =>
                    setSheetState(() => waterMl = (v / 50).round() * 50),
              ),
              Text('Удобрение: раз в $fertilizer дн.'),
              Slider(
                value: fertilizer.toDouble(),
                min: 7,
                max: 90,
                divisions: 83,
                activeColor: AppColors.primary,
                onChanged: (v) => setSheetState(() => fertilizer = v.round()),
              ),
              TextField(
                controller: lightCtrl,
                decoration: const InputDecoration(hintText: 'Освещение'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tempCtrl,
                decoration: const InputDecoration(hintText: 'Температура'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      final api = ref.read(apiProvider);
      await api.dio.patch('/api/plants/${plant.id}', data: {
        'care': {
          'wateringIntervalDays': watering,
          'waterAmountMl': waterMl,
          'fertilizerIntervalDays': fertilizer,
          'light': lightCtrl.text.trim(),
          'temperature': tempCtrl.text.trim(),
        },
      });
      ref.invalidate(plantDetailsProvider(plant.id));
      await ref.read(plantsProvider.notifier).reload();
    }
  }

  Future<void> _addJournalEntry(
      BuildContext context, WidgetRef ref, String plantId) async {
    final noteCtrl = TextEditingController();
    XFile? photo;
    var kind = 'progress';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Запись в журнал',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final (value, label) in [
                    ('before', 'До'),
                    ('after', 'После'),
                    ('progress', 'Прогресс'),
                  ]) ...[
                    ChoiceChip(
                      label: Text(label),
                      selected: kind == value,
                      selectedColor: AppColors.secondaryContainer,
                      onSelected: (_) => setSheetState(() => kind = value),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1600,
                      imageQuality: 88);
                  if (picked != null) setSheetState(() => photo = picked);
                },
                icon: const Icon(Icons.photo_outlined, size: 19),
                label: Text(photo == null ? 'Прикрепить фото' : 'Фото выбрано ✓'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration:
                    const InputDecoration(hintText: 'Заметка о состоянии…'),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Сохранить запись'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true && (photo != null || noteCtrl.text.trim().isNotEmpty)) {
      final api = ref.read(apiProvider);
      final form = FormData.fromMap({
        'note': noteCtrl.text.trim(),
        'kind': kind,
        if (photo != null)
          'photo':
              await MultipartFile.fromFile(photo!.path, filename: 'journal.jpg'),
      });
      await api.dio.post('/api/plants/$plantId/journal', data: form);
      ref.invalidate(plantDetailsProvider(plantId));
      await ref.read(plantsProvider.notifier).reload();
    }
  }
}

String stageLabel(String stage) {
  switch (stage) {
    case 'seed':
      return 'Семя';
    case 'sprout':
      return 'Росток';
    case 'seedling':
      return 'Саженец';
    case 'growing':
      return 'Растёт';
    case 'flowering':
      return 'Цветёт';
    case 'mature':
    default:
      return 'Взрослое';
  }
}

class _CheckupCard extends StatelessWidget {
  const _CheckupCard({required this.plant, required this.onCheckup});

  final Plant plant;
  final VoidCallback onCheckup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = plant.checkupDueAt;
    final overdue = plant.needsCheckup;
    String when;
    if (due == null) {
      when = 'по расписанию';
    } else {
      final days = due.difference(DateTime.now()).inDays;
      if (overdue || days <= 0) {
        when = 'пора обновить фото';
      } else {
        when = 'через $days дн. (${DateFormat('d MMM', 'ru').format(due)})';
      }
    }
    return SoftCard(
      color: overdue ? AppColors.terracottaContainer : AppColors.mintSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_outlined,
                  size: 19,
                  color: overdue ? AppColors.terracotta : AppColors.secondary),
              const SizedBox(width: 8),
              Text('КОНТРОЛЬ СОСТОЯНИЯ',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: overdue ? AppColors.terracotta : AppColors.secondary,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plant.isGrown
                ? 'ИИ следит за ростом. Новое фото: $when.'
                : 'Периодически обновляйте фото — ИИ сравнит и обновит состояние. Новое фото: $when.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCheckup,
              icon: const Icon(Icons.add_a_photo_outlined, size: 19),
              label: const Text('Перефотографировать'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareTile extends StatelessWidget {
  const _CareTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.secondaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21,
              color: highlight ? AppColors.primary : AppColors.secondary),
          const SizedBox(height: 8),
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (kindLabel, kindColor) = switch (entry.kind) {
      'before' => ('ДО', AppColors.terracotta),
      'after' => ('ПОСЛЕ', AppColors.secondary),
      _ => ('ПРОГРЕСС', AppColors.outline),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.photoUrl != null)
              PlantImage(url: entry.photoUrl, height: 170, width: double.infinity),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: kindColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '$kindLabel (${DateFormat('d MMM', 'ru').format(entry.createdAt)})',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8),
                ),
              ],
            ),
            if (entry.healthScore != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    entry.trend == 'up'
                        ? Icons.trending_up
                        : entry.trend == 'down'
                            ? Icons.trending_down
                            : Icons.trending_flat,
                    size: 16,
                    color: entry.trend == 'up'
                        ? AppColors.secondary
                        : entry.trend == 'down'
                            ? AppColors.terracotta
                            : AppColors.outline,
                  ),
                  const SizedBox(width: 6),
                  Text('ИИ-оценка: ${entry.healthScore}/100',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: entry.healthScore! / 100,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceContainer,
                  valueColor: AlwaysStoppedAnimation(
                    entry.healthScore! >= 70
                        ? AppColors.secondary
                        : entry.healthScore! >= 45
                            ? const Color(0xFFB77B1F)
                            : AppColors.terracotta,
                  ),
                ),
              ),
              if ((entry.analysis ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(entry.analysis!, style: theme.textTheme.bodyMedium),
              ],
            ],
            if (entry.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.note, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.plant});

  final Plant plant;

  String _relative(DateTime? due) {
    if (due == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    final diff = target.difference(today).inDays;
    if (diff < 0) return 'просрочено';
    if (diff == 0) return 'сегодня';
    if (diff == 1) return 'завтра';
    return 'через $diff дн.';
  }

  Set<int> _dueDays(DateTime? due, int interval) {
    final result = <int>{};
    if (due == null) return result;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final step = interval > 0 ? interval : 7;
    var d = DateTime(due.year, due.month, due.day);
    while (d.difference(today).inDays < 14) {
      final idx = d.difference(today).inDays;
      if (idx >= 0 && idx < 14) result.add(idx);
      d = d.add(Duration(days: step));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final waterDays = _dueDays(plant.wateringDueAt, plant.care.wateringIntervalDays);
    final fertDays =
        _dueDays(plant.fertilizingDueAt, plant.care.fertilizerIntervalDays);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _NextEventTile(
                  icon: Icons.water_drop_rounded,
                  color: AppColors.secondary,
                  title: 'Полив',
                  when: _relative(plant.wateringDueAt),
                  detail:
                      '${plant.care.waterAmountMl} мл • раз в ${plant.care.wateringIntervalDays} дн.',
                  urgent: plant.needsWater,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NextEventTile(
                  icon: Icons.eco_rounded,
                  color: const Color(0xFFB77B1F),
                  title: 'Удобрение',
                  when: _relative(plant.fertilizingDueAt),
                  detail: 'раз в ${plant.care.fertilizerIntervalDays} дн.',
                  urgent: plant.needsFertilizer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('БЛИЖАЙШИЕ 2 НЕДЕЛИ',
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
          const SizedBox(height: 10),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final day = today.add(Duration(days: i));
                final isWater = waterDays.contains(i);
                final isFert = fertDays.contains(i);
                final active = isWater || isFert;
                return Container(
                  width: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.secondaryContainer
                        : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(DateFormat('E', 'ru').format(day).toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(fontSize: 9)),
                      const SizedBox(height: 2),
                      Text('${day.day}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isWater)
                            const Icon(Icons.water_drop,
                                size: 10, color: AppColors.secondary),
                          if (isFert)
                            const Icon(Icons.eco,
                                size: 10, color: Color(0xFFB77B1F)),
                          if (!active) const SizedBox(height: 10),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NextEventTile extends StatelessWidget {
  const _NextEventTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.when,
    required this.detail,
    this.urgent = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String when;
  final String detail;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: urgent
            ? AppColors.secondaryContainer
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(title,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(when,
              style: theme.textTheme.titleMedium?.copyWith(
                color: urgent ? AppColors.primary : AppColors.onSurface,
              )),
          const SizedBox(height: 2),
          Text(detail,
              style: theme.textTheme.labelSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
