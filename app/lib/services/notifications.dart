import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

/// Локальные уведомления о поливе. Расписание пересобирается
/// при каждой синхронизации списка растений.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Показать уведомление прямо сейчас (для foreground-пушей FCM).
  Future<void> showNow({
    required int id,
    String? title,
    String? body,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'watering',
          'Напоминания о поливе',
          channelDescription: 'Уведомления о поливе и уходе',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> syncWateringReminders(List<Plant> plants) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    var id = 1;
    for (final plant in plants) {
      final due = plant.wateringDueAt;
      if (due == null) continue;
      var when = tz.TZDateTime.from(due, tz.local);
      final now = tz.TZDateTime.now(tz.local);
      // Просроченный полив — напоминаем через час, а не в прошлом.
      if (when.isBefore(now)) when = now.add(const Duration(hours: 1));
      try {
        await _plugin.zonedSchedule(
          id: id++,
          title: 'Пора полить: ${plant.name}',
          body: 'Загляните в Sprout AI и отметьте полив 💧',
          scheduledDate: when,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'watering',
              'Напоминания о поливе',
              channelDescription: 'Уведомления, когда растению нужен полив',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (_) {
        // Без разрешения на точные будильники просто пропускаем.
      }
      if (id > 60) break;
    }
  }
}
