import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../models/weekly_history.dart';
import 'common.dart';

class WeeklyPlantHistory extends StatefulWidget {
  const WeeklyPlantHistory({
    super.key,
    required this.weeks,
    required this.journal,
  });
  final List<PlantWeek> weeks;
  final List<JournalEntry> journal;

  @override
  State<WeeklyPlantHistory> createState() => _WeeklyPlantHistoryState();
}

class _WeeklyPlantHistoryState extends State<WeeklyPlantHistory> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos =
        widget.journal.where((e) => e.photoUrl?.isNotEmpty == true).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Одно контрольное фото раз в неделю. Пустые недели показаны явно — '
          'по ним нельзя судить об изменении здоровья.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (widget.weeks.isEmpty)
          const SoftCard(
            child: Text('Добавьте первое фото, чтобы начать историю.'),
          )
        else
          SizedBox(
            height: 280 + (scale - 1).clamp(0, 2) * 100,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: widget.weeks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final week = widget.weeks[index];
                final entry = week.latestPhoto;
                return SizedBox(
                  width: 216,
                  child: SoftCard(
                    padding: const EdgeInsets.all(12),
                    onTap: week.entries.isEmpty
                        ? null
                        : () => _openWeek(context, week),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Неделя ${week.weekNumber}',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          '${DateFormat('d MMM', 'ru').format(week.weekStart.toLocal())} — '
                          '${DateFormat('d MMM', 'ru').format(week.weekEnd.subtract(const Duration(milliseconds: 1)).toLocal())}',
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: entry == null
                              ? Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        week.status == 'missed'
                                            ? Icons.image_not_supported_outlined
                                            : Icons.add_a_photo_outlined,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        week.status == 'missed'
                                            ? 'Фото пропущено'
                                            : 'Ждём фото',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                )
                              : PlantImage(
                                  url: entry.photoUrl,
                                  width: double.infinity,
                                  radius: 16,
                                ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          entry?.healthScore == null
                              ? 'Без ИИ-оценки'
                              : '${entry!.healthScore}/100 · ${healthTrendLabel(entry.trend)}',
                          style: theme.textTheme.labelMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (week.entries.isNotEmpty)
                          Text(
                            'Фото: ${week.photos.length} · открыть',
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (photos.length >= 2) ...[
          const SizedBox(height: 20),
          Text('Первое фото и последнее', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _photoLabel(context, photos.first)),
              const SizedBox(width: 12),
              Expanded(child: _photoLabel(context, photos.last)),
            ],
          ),
        ],
        if (widget.weeks.any(
          (w) => w.entries.any((e) => e.healthScore != null),
        )) ...[
          const SizedBox(height: 20),
          Text(
            'Оценки здоровья по неделям',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            width: double.infinity,
            child: Semantics(
              label:
                  'График оценок от 0 до 100. Пропущенные недели не соединяются.',
              child: CustomPaint(
                painter: _HealthHistoryPainter(
                  widget.weeks,
                  theme.colorScheme.primary,
                  theme.colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          Text(
            'Пропуск — разрыв линии. ИИ-оценки приблизительны.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }

  Widget _photoLabel(BuildContext context, JournalEntry entry) =>
      GestureDetector(
        onTap: () => _openPhoto(context, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlantImage(
              url: entry.photoUrl,
              height: 180,
              width: double.infinity,
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('d MMM yyyy', 'ru').format(entry.createdAt.toLocal()),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (entry.healthScore != null) Text('${entry.healthScore}/100'),
          ],
        ),
      );

  void _openWeek(BuildContext context, PlantWeek week) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: .8,
        maxChildSize: .95,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Неделя ${week.weekNumber}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            for (final entry in week.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.photoUrl?.isNotEmpty == true)
                      GestureDetector(
                        onTap: () => _openPhoto(context, entry),
                        child: PlantImage(
                          url: entry.photoUrl,
                          height: 260,
                          width: double.infinity,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat(
                        'd MMMM, HH:mm',
                        'ru',
                      ).format(entry.createdAt.toLocal()),
                    ),
                    if (entry.healthScore != null)
                      Text(
                        '${entry.healthScore}/100 · ${healthTrendLabel(entry.trend)}',
                      ),
                    if (entry.diagnosisTitle.isNotEmpty)
                      Text(
                        entry.diagnosisTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (entry.analysis?.isNotEmpty == true)
                      Text(entry.analysis!),
                    if (entry.note.isNotEmpty) Text(entry.note),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openPhoto(BuildContext context, JournalEntry entry) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            DateFormat('d MMMM yyyy', 'ru').format(entry.createdAt.toLocal()),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: PlantImage(
              url: entry.photoUrl,
              width: double.infinity,
              radius: 0,
            ),
          ),
        ),
      ),
    ),
  );
}

class _HealthHistoryPainter extends CustomPainter {
  _HealthHistoryPainter(this.weeks, this.color, this.gridColor);
  final List<PlantWeek> weeks;
  final Color color;
  final Color gridColor;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final value in [0, 50, 100]) {
      final y = 8 + (100 - value) / 100 * (size.height - 16);
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), grid);
    }
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    Offset? previous;
    for (var i = 0; i < weeks.length; i++) {
      final scored = weeks[i].entries
          .where((e) => e.healthScore != null)
          .toList();
      if (scored.isEmpty) {
        previous = null;
        continue;
      }
      final x = weeks.length == 1
          ? size.width / 2
          : 5 + i / (weeks.length - 1) * (size.width - 10);
      final y =
          8 +
          (100 - scored.last.healthScore!.clamp(0, 100)) /
              100 *
              (size.height - 16);
      final point = Offset(x, y);
      if (previous != null) canvas.drawLine(previous, point, pen);
      canvas.drawCircle(point, 4, pen);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _HealthHistoryPainter old) =>
      old.weeks != weeks || old.color != color || old.gridColor != gridColor;
}
