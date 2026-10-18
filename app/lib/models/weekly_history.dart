import 'models.dart';

class PlantWeek {
  const PlantWeek({
    required this.weekStart,
    required this.weekEnd,
    required this.weekNumber,
    required this.status,
    required this.entries,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final int weekNumber;
  final String status;
  final List<JournalEntry> entries;

  List<JournalEntry> get photos =>
      entries.where((entry) => entry.photoUrl?.isNotEmpty == true).toList();

  JournalEntry? get latestPhoto => photos.isEmpty ? null : photos.last;

  factory PlantWeek.fromJson(Map<String, dynamic> json) {
    final entries =
        ((json['entries'] ?? []) as List)
            .map(
              (value) =>
                  JournalEntry.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return PlantWeek(
      weekStart: DateTime.parse(json['weekStart'] as String),
      weekEnd: DateTime.parse(json['weekEnd'] as String),
      weekNumber: (json['weekNumber'] as num).toInt(),
      status: (json['status'] ?? 'upcoming') as String,
      entries: entries,
    );
  }
}

/// Compatibility with an older server. Missing photos stay missing; a note or
/// the current cover image must never be presented as a historical photograph.
List<PlantWeek> buildWeeklyHistory(
  Plant plant,
  List<JournalEntry> journal, {
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toUtc();
  final ordered =
      journal.where((entry) => !entry.createdAt.isAfter(clock)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  var start =
      (plant.createdAt ?? (ordered.isEmpty ? clock : ordered.first.createdAt))
          .toUtc();
  if (start.isAfter(clock)) start = clock;
  if (ordered.isNotEmpty && ordered.first.createdAt.isBefore(start)) {
    start = ordered.first.createdAt.toUtc();
  }
  const week = Duration(days: 7);
  final current = clock.difference(start).inMilliseconds ~/ week.inMilliseconds;
  return List.generate(current + 1, (index) {
    final from = start.add(week * index);
    final until = from.add(week);
    final entries = ordered
        .where(
          (entry) =>
              !entry.createdAt.isBefore(from) &&
              entry.createdAt.isBefore(until),
        )
        .toList();
    final hasPhoto = entries.any((entry) => entry.photoUrl?.isNotEmpty == true);
    return PlantWeek(
      weekStart: from,
      weekEnd: until,
      weekNumber: index + 1,
      status: hasPhoto
          ? 'recorded'
          : index == current
          ? 'upcoming'
          : 'missed',
      entries: entries,
    );
  });
}

String healthTrendLabel(String? trend) => switch (trend) {
  'up' => 'Улучшается',
  'down' => 'Стало хуже',
  'same' => 'Без заметных изменений',
  _ => 'Первая оценка',
};

String plantHealthLabel(String status) => switch (status) {
  'thriving' => 'Проблем не обнаружено',
  'needs_attention' => 'Есть проблемы',
  'sick' => 'Нужно лечение',
  _ => 'Нужна проверка',
};
