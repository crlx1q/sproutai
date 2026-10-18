import 'package:flutter_test/flutter_test.dart';
import 'package:sprout_ai/models/models.dart';
import 'package:sprout_ai/models/weekly_history.dart';

void main() {
  final start = DateTime.utc(2026, 9, 1);
  Plant plant() => Plant.fromJson({
    '_id': 'a',
    'name': 'Бамбук у окна',
    'createdAt': start.toIso8601String(),
    'healthScore': 72.0,
    'healthStatus': 'needs_attention',
    'healthTrend': 'up',
    'previousHealthScore': 55,
  });
  JournalEntry entry(int day, {bool photo = true}) => JournalEntry(
    id: '$day',
    photoUrl: photo ? '/photo-$day.jpg' : null,
    note: photo ? '' : 'Заметка без фото',
    kind: 'progress',
    createdAt: start.add(Duration(days: day)),
    healthScore: photo ? 60 + day : null,
  );

  test('missing weeks stay visible and note-only week is not a photo', () {
    final weeks = buildWeeklyHistory(plant(), [
      entry(0),
      entry(9, photo: false),
      entry(21),
    ], now: start.add(const Duration(days: 24)));
    expect(weeks.map((week) => week.status), [
      'recorded',
      'missed',
      'missed',
      'recorded',
    ]);
    expect(weeks[1].entries.single.note, 'Заметка без фото');
    expect(weeks[2].entries, isEmpty);
  });

  test('photo on week boundary belongs to next week, current gap upcoming', () {
    final weeks = buildWeeklyHistory(plant(), [
      entry(0),
      entry(7),
    ], now: start.add(const Duration(days: 15)));
    expect(weeks.map((week) => week.status), [
      'recorded',
      'recorded',
      'upcoming',
    ]);
    expect(weeks[1].entries.single.id, '7');
  });

  test('improvement is independent from current unresolved diagnosis', () {
    final current = plant();
    expect(current.healthTrend, 'up');
    expect(current.healthStatus, 'needs_attention');
    expect(current.previousHealthScore, 55);
    expect(current.healthScore, 72);
    expect(healthTrendLabel(current.healthTrend), 'Улучшается');
  });

  test('expired Pro is shown as expired on client', () {
    final user = User.fromJson({
      'id': 'u',
      'email': 'a@b.c',
      'name': 'A',
      'plan': 'pro',
      'proUntil': '2000-01-01T00:00:00Z',
    });
    expect(user.isPro, isFalse);
  });
}
