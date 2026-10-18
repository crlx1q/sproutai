import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../models/weekly_history.dart';
import '../providers/plants_provider.dart';
import '../widgets/common.dart';
import '../widgets/plant_history.dart';

class PlantScreen extends ConsumerStatefulWidget {
  const PlantScreen({super.key, required this.plantId});
  final String plantId;
  @override
  ConsumerState<PlantScreen> createState() => _PlantScreenState();
}

class _PlantScreenState extends ConsumerState<PlantScreen> {
  bool _busy = false;
  PlantsNotifier get _plants => ref.read(plantsProvider.notifier);

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _perform(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _message(success);
    } catch (error) {
      _message(apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(plantDetailsProvider(widget.plantId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моё растение'),
        actions: [
          if (details.value != null)
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) {
                if (value == 'rename') _rename(details.value!.plant);
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Имя и место')),
                PopupMenuItem(value: 'delete', child: Text('Удалить растение')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: details.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(apiErrorMessage(error), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(
                          plantDetailsProvider(widget.plantId),
                        ),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
              data: _content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(PlantDetails details) {
    final plant = details.plant;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final diagnosis = plant.lastDiagnosis;
    final weeks = details.weeklyHistory.isNotEmpty
        ? details.weeklyHistory
        : buildWeeklyHistory(plant, details.journal);
    final notes = details.journal
        .where((entry) => entry.photoUrl?.isNotEmpty != true)
        .toList();
    final quota = ref.watch(scanQuotaProvider).value;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(plantDetailsProvider(plant.id));
        await ref.read(plantDetailsProvider(plant.id).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          PlantImage(url: plant.photoUrl, height: 250, width: double.infinity),
          const SizedBox(height: 16),
          Text(plant.name, style: theme.textTheme.headlineLarge),
          if (plant.species.isNotEmpty)
            Text(plant.species, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(plant.location == 'outdoor' ? 'На улице' : 'В помещении'),
              if (plant.isGrown) Text('🌱 ${stageLabel(plant.stage)}'),
              TextButton.icon(
                onPressed: _busy ? null : () => _rename(plant),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Подписать'),
              ),
            ],
          ),
          if (plant.growthGoal.isNotEmpty) Text('Цель: ${plant.growthGoal}'),
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Текущее состояние', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${plant.healthScore}/100',
                      style: theme.textTheme.headlineMedium,
                    ),
                    StatusChip(status: plant.healthStatus),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: plant.healthScore.clamp(0, 100) / 100,
                    minHeight: 8,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: plant.healthStatus == 'sick'
                        ? colors.error
                        : colors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  healthTrendLabel(plant.healthTrend),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: plant.healthTrend == 'down'
                        ? colors.error
                        : colors.primary,
                  ),
                ),
                if (plant.previousHealthScore != null)
                  Text('Предыдущая оценка: ${plant.previousHealthScore}/100'),
                if (plant.lastProgressNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(plant.lastProgressNote),
                ],
                if (plant.healthTrend == 'up' &&
                    plant.healthStatus != 'thriving') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Есть улучшение, но признаки проблемы ещё сохраняются. '
                    'Продолжайте план ухода до следующего фото.',
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Оценка относится к последнему фото. Между проверками состояние неизвестно.',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            color: colors.secondaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Еженедельное фото',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Следующая проверка: ${_when(plant.checkupDueAt)}. '
                  'Снимайте с похожего ракурса и при похожем освещении.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _checkup(plant),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Обновить фото и проверить'),
                ),
                const SizedBox(height: 6),
                Text(
                  quota == null
                      ? 'ИИ сравнит новое фото с предыдущим состоянием.'
                      : quota.isUnlimited
                      ? 'ИИ-проверки без ограничений'
                      : 'Осталось ИИ-проверок: ${quota.remaining}. Фото без ИИ можно сохранить в дневник.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (diagnosis != null) ...[
            const SizedBox(height: 20),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(diagnosis.title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(diagnosis.description),
                  if (diagnosis.treatmentPlan.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final step in diagnosis.treatmentPlan.asMap().entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${step.key + 1}. ${step.value}'),
                      ),
                  ],
                  if (diagnosis.scannedAt != null)
                    Text(
                      'Фото от ${_date(diagnosis.scannedAt!)}',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('Уход и отметки', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          _CareActionCard(
            title: 'Полив',
            icon: Icons.water_drop_outlined,
            due: _when(plant.wateringDueAt),
            detail:
                '${plant.care.waterAmountMl} мл · раз в ${plant.care.wateringIntervalDays} дн.',
            last: plant.lastWateredAt == null
                ? 'Ещё не отмечен'
                : 'Последний: ${_date(plant.lastWateredAt!)}',
            urgent: plant.needsWater,
            enabled: !_busy,
            onDone: () => _perform(
              () => _plants.water(plant.id),
              'Полив отмечен. Расписание обновлено.',
            ),
            onLater: () => _perform(
              () => _plants.snooze(plant.id, 'watering'),
              'Полив отложен до завтра.',
            ),
            doneLabel: 'Полил(а)',
          ),
          const SizedBox(height: 12),
          _CareActionCard(
            title: 'Удобрение',
            icon: Icons.eco_outlined,
            due: _when(plant.fertilizingDueAt),
            detail: 'Раз в ${plant.care.fertilizerIntervalDays} дн.',
            last: plant.lastFertilizedAt == null
                ? 'Ещё не отмечено'
                : 'Последнее: ${_date(plant.lastFertilizedAt!)}',
            urgent: plant.needsFertilizer,
            enabled: !_busy,
            onDone: () => _perform(
              () => _plants.fertilize(plant.id),
              'Подкормка отмечена. Следующий срок пересчитан.',
            ),
            onLater: () => _perform(
              () => _plants.snooze(plant.id, 'fertilizing'),
              'Подкормка отложена до завтра.',
            ),
            doneLabel: 'Удобрил(а)',
          ),
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Условия', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _condition(Icons.wb_sunny_outlined, 'Свет', plant.care.light),
                _condition(
                  Icons.thermostat_outlined,
                  'Температура',
                  plant.care.temperature,
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _editCare(plant),
                  icon: const Icon(Icons.tune),
                  label: const Text('Изменить расписание и условия'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('История по неделям', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          WeeklyPlantHistory(weeks: weeks, journal: details.journal),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _addEntry(plant),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Добавить фото или заметку'),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Заметки', style: theme.textTheme.titleLarge),
            for (final entry in notes)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _date(entry.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                      Text(entry.note),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _condition(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text('$title: $value')),
      ],
    ),
  );

  Future<ImageSource?> _source() => showModalBottomSheet<ImageSource>(
    context: context,
    useSafeArea: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Сделать фото'),
            onTap: () => Navigator.pop(sheet, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Выбрать из галереи'),
            onTap: () => Navigator.pop(sheet, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );

  Future<void> _checkup(Plant plant) async {
    if (_busy) return;
    try {
      final source = await _source();
      if (source == null || !mounted) return;
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 88,
      );
      if (image == null || !mounted) return;
      setState(() => _busy = true);
      try {
        final data = await _plants.checkup(
          plant.id,
          await MultipartFile.fromFile(image.path, filename: 'checkup.jpg'),
        );
        if (!mounted) return;
        final result = Map<String, dynamic>.from(data['result'] as Map);
        final updated = Plant.fromJson(
          Map<String, dynamic>.from(data['plant'] as Map),
        );
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            scrollable: true,
            title: Text(
              '${updated.healthScore}/100 · ${healthTrendLabel(updated.healthTrend)}',
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plantHealthLabel(updated.healthStatus)),
                const SizedBox(height: 8),
                Text(
                  updated.lastProgressNote.isNotEmpty
                      ? updated.lastProgressNote
                      : (result['progressNote'] ??
                                result['diagnosis']?['description'] ??
                                '')
                            .toString(),
                ),
                const SizedBox(height: 12),
                for (final advice in (result['growthAdvice'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $advice'),
                  ),
                const Text(
                  'Фото сохранено в недельной истории. Следующая проверка через 7 дней.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 402 || !mounted) rethrow;
        final save = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            scrollable: true,
            title: const Text('Лимит ИИ-проверок исчерпан'),
            content: const Text(
              'Сохранить фото в историю без ИИ-оценки? Состояние и дата контрольной проверки останутся прежними.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Сохранить фото'),
              ),
            ],
          ),
        );
        if (save == true && mounted) {
          await _plants.addJournal(
            plant.id,
            photo: await MultipartFile.fromFile(
              image.path,
              filename: 'progress.jpg',
            ),
            analyze: false,
          );
          _message('Фото сохранено без ИИ-оценки.');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } catch (error) {
      _message(apiErrorMessage(error));
    }
  }

  Future<void> _rename(Plant plant) async {
    final name = TextEditingController(text: plant.name);
    var location = plant.location;
    final key = GlobalKey<FormState>();
    final saved = await _formDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('Личное имя растения'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Имя или место',
                    hintText: 'Бамбук у окна',
                  ),
                  validator: (value) =>
                      value?.trim().isEmpty != false ? 'Введите имя' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: location,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Расположение'),
                  items: const [
                    DropdownMenuItem(
                      value: 'indoor',
                      child: Text('В помещении'),
                    ),
                    DropdownMenuItem(value: 'outdoor', child: Text('На улице')),
                  ],
                  onChanged: (value) =>
                      update(() => location = value ?? 'indoor'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(dialog, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (saved == true && mounted) {
      await _perform(
        () => _plants.updatePlant(plant.id, {
          'name': value,
          'location': location,
        }),
        'Имя растения сохранено.',
      );
    }
  }

  Future<void> _editCare(Plant plant) async {
    final water = TextEditingController(
      text: '${plant.care.wateringIntervalDays}',
    );
    final amount = TextEditingController(text: '${plant.care.waterAmountMl}');
    final fertilizer = TextEditingController(
      text: '${plant.care.fertilizerIntervalDays}',
    );
    final light = TextEditingController(text: plant.care.light);
    final temperature = TextEditingController(text: plant.care.temperature);
    final key = GlobalKey<FormState>();
    final saved = await _formDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Расписание и условия'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in [
                (water, 'Полив: интервал, дней', 365),
                (amount, 'Воды за полив, мл', 10000),
                (fertilizer, 'Подкормка: интервал, дней', 365),
              ]) ...[
                TextFormField(
                  controller: field.$1,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: field.$2),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 1 || number > field.$3
                        ? 'Введите от 1 до ${field.$3}'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: light,
                decoration: const InputDecoration(labelText: 'Освещение'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: temperature,
                decoration: const InputDecoration(labelText: 'Температура'),
              ),
              const SizedBox(height: 12),
              const Text('Контрольное фото — раз в 7 дней.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(dialog, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    final care = saved == true
        ? {
            'wateringIntervalDays': int.parse(water.text),
            'waterAmountMl': int.parse(amount.text),
            'fertilizerIntervalDays': int.parse(fertilizer.text),
            'light': light.text.trim(),
            'temperature': temperature.text.trim(),
            'checkupIntervalDays': 7,
          }
        : null;
    for (final controller in [water, amount, fertilizer, light, temperature]) {
      controller.dispose();
    }
    if (care != null && mounted) {
      await _perform(
        () => _plants.updatePlant(plant.id, {'care': care}),
        'Условия и расписание сохранены.',
      );
    }
  }

  Future<void> _addEntry(Plant plant) async {
    final note = TextEditingController();
    XFile? photo;
    final saved = await _formDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('Фото или заметка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Например: пересадил(а), появился новый лист',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_outlined),
                label: Text(photo == null ? 'Прикрепить фото' : 'Фото выбрано'),
                onPressed: () async {
                  try {
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1600,
                      imageQuality: 88,
                    );
                    if (context.mounted && picked != null) {
                      update(() => photo = picked);
                    }
                  } catch (error) {
                    _message(apiErrorMessage(error));
                  }
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Дневник без ИИ — бесплатно. Для новой оценки используйте еженедельную проверку.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                if (photo == null && note.text.trim().isEmpty) {
                  _message('Добавьте фото или текст заметки.');
                  return;
                }
                Navigator.pop(dialog, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final noteText = note.text.trim();
    note.dispose();
    if (saved == true && mounted) {
      await _perform(() async {
        await _plants.addJournal(
          plant.id,
          note: noteText,
          analyze: false,
          photo: photo == null
              ? null
              : await MultipartFile.fromFile(
                  photo!.path,
                  filename: 'journal.jpg',
                ),
        );
      }, 'Запись сохранена в истории.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Удалить растение?'),
        content: const Text('Его история и напоминания тоже будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() async {
      await _plants.deletePlant(widget.plantId);
      if (mounted) context.go('/home');
    }, 'Растение удалено.');
  }
}

class _CareActionCard extends StatelessWidget {
  const _CareActionCard({
    required this.title,
    required this.icon,
    required this.due,
    required this.detail,
    required this.last,
    required this.urgent,
    required this.enabled,
    required this.onDone,
    required this.onLater,
    required this.doneLabel,
  });
  final String title, due, detail, last, doneLabel;
  final IconData icon;
  final bool urgent, enabled;
  final VoidCallback onDone, onLater;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            due,
            style: theme.textTheme.titleMedium?.copyWith(
              color: urgent
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(detail),
          Text(last, style: theme.textTheme.labelSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: enabled ? onDone : null,
                icon: const Icon(Icons.check, size: 18),
                label: Text(doneLabel),
              ),
              TextButton(
                onPressed: enabled ? onLater : null,
                child: const Text('Не сейчас · завтра'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<T?> _formDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  // Closing TextFields still participate in the route's reverse transition.
  await route.completed;
  return result;
}

String _date(DateTime value) =>
    DateFormat('d MMMM yyyy', 'ru').format(value.toLocal());
String _when(DateTime? value) {
  if (value == null) return 'Дата пока не определена';
  final due = value.toLocal();
  final now = DateTime.now();
  final days = DateTime(
    due.year,
    due.month,
    due.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days < 0) return 'Пора · с ${DateFormat('d MMM', 'ru').format(due)}';
  if (days == 0) return 'Сегодня';
  if (days == 1) return 'Завтра';
  return '${DateFormat('d MMM', 'ru').format(due)} · через $days дн.';
}

String stageLabel(String stage) => switch (stage) {
  'seed' => 'Семя',
  'sprout' => 'Росток',
  'seedling' => 'Саженец',
  'growing' => 'Растёт',
  'flowering' => 'Цветёт',
  _ => 'Взрослое',
};
