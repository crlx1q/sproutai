import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

class PlantReminder {
  const PlantReminder(this.plantId, this.type, this.name, this.dueAt);
  final String plantId;
  final String type;
  final String name;
  final DateTime dueAt;

  String get cycle => '$plantId:$type:${dueAt.toUtc().toIso8601String()}';
  int get id {
    var hash = 0x811c9dc5;
    for (final unit in '$plantId:$type'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x3fffffff;
    }
    return 0x20000000 + hash;
  }

  String get title => switch (type) {
    'watering' => 'Пора полить: $name 💧',
    'fertilizing' => 'Подкормка: $name 🌱',
    _ => 'Еженедельное фото: $name 📸',
  };
  String get body => switch (type) {
    'watering' => 'Проверьте грунт и отметьте полив в Sprout AI.',
    'fertilizing' => 'Отметьте подкормку или отложите напоминание.',
    _ => 'Сделайте фото, чтобы сравнить состояние и сохранить историю роста.',
  };
}

List<PlantReminder> planPlantReminders(List<Plant> plants) {
  final reminders = <PlantReminder>[];
  for (final plant in plants) {
    final dates = {
      'watering': plant.wateringDueAt,
      'fertilizing': plant.fertilizingDueAt,
      'checkup': plant.checkupDueAt,
    };
    for (final entry in dates.entries) {
      if (entry.value != null && plant.isReminderEnabled(entry.key)) {
        reminders.add(
          PlantReminder(plant.id, entry.key, plant.name, entry.value!),
        );
      }
    }
  }
  reminders.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  // iOS retains at most 64 pending local notifications.
  return reminders.take(60).toList();
}

/// Local fallback when this device cannot use the server's FCM integration.
/// Absolute API timestamps are scheduled in UTC; this avoids an uninitialized
/// tz.local and preserves the correct instant across device timezone changes.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _storageKey = 'sprout.reminders.v2';
  static const _channel = AndroidNotificationChannel(
    'watering',
    'Уход за растениями',
    description: 'Полив, подкормка и еженедельные фото растений',
    importance: Importance.high,
  );
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'watering',
      'Уход за растениями',
      channelDescription: 'Полив, подкормка и еженедельные фото растений',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(),
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  final _plantOpen = StreamController<String>.broadcast();
  Future<void> _queue = Future.value();
  bool _ready = false;
  int _revision = 0;
  String? _pendingPlantId;

  Stream<String> get onPlantOpen => _plantOpen.stream;
  String? takePendingPlantId() {
    final value = _pendingPlantId;
    _pendingPlantId = null;
    return value;
  }

  void openPlant(String? plantId) {
    if (plantId == null || !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(plantId)) {
      return;
    }
    _pendingPlantId = plantId;
    _plantOpen.add(plantId);
  }

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) =>
            openPlant(response.payload),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        openPlant(launch?.notificationResponse?.payload);
      }
      _ready = true;
    } catch (error) {
      debugPrint(
        '[notifications] Initialization unavailable: ${error.runtimeType}',
      );
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } catch (error) {
      debugPrint(
        '[notifications] Permission unavailable: ${error.runtimeType}',
      );
      return false;
    }
  }

  Future<void> showNow({
    required int id,
    String? title,
    String? body,
    String? plantId,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id & 0x0fffffff,
        title: title,
        body: body,
        notificationDetails: _details,
        payload: plantId,
      );
    } catch (error) {
      debugPrint('[notifications] Display failed: ${error.runtimeType}');
    }
  }

  Future<void> _serialize(Future<void> Function() work) {
    _queue = _queue.then((_) => work()).catchError((Object error) {
      debugPrint('[notifications] Schedule failed: ${error.runtimeType}');
    });
    return _queue;
  }

  Future<void> cancelAll() {
    _revision++;
    _pendingPlantId = null;
    return _serialize(() async {
      if (!_ready) return;
      await _plugin.cancelAll();
      await (await SharedPreferences.getInstance()).remove(_storageKey);
    });
  }

  Future<void> cancelReminders() {
    _revision++;
    return _serialize(() async {
      if (!_ready) return;
      final prefs = await SharedPreferences.getInstance();
      final saved = _readSaved(prefs);
      final ids = (await _plugin.pendingNotificationRequests())
          .map((item) => item.id)
          .where(_isReminderId)
          .toSet();
      ids.addAll(saved.keys.map(int.tryParse).whereType<int>());
      for (final id in ids) {
        await _plugin.cancel(id: id);
      }
      await prefs.remove(_storageKey);
    });
  }

  Map<String, dynamic> _readSaved(SharedPreferences prefs) {
    try {
      return jsonDecode(prefs.getString(_storageKey) ?? '{}')
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  bool _isReminderId(int id) => id >= 0x20000000 && id <= 0x5fffffff;

  /// Preserves already delivered overdue cycles instead of re-arming on each reload.
  Future<void> syncWateringReminders(List<Plant> plants) {
    final revision = ++_revision;
    return _serialize(() async {
      if (!_ready || revision != _revision) return;
      final prefs = await SharedPreferences.getInstance();
      final previous = _readSaved(prefs);
      final requests = await _plugin.pendingNotificationRequests();
      final pending = requests.map((item) => item.id).toSet();
      final pendingTitles = {for (final item in requests) item.id: item.title};
      final next = <String, String>{};
      final plans = planPlantReminders(plants);
      for (final plan in plans) {
        if (revision != _revision) return;
        final key = '${plan.id}';
        next[key] = plan.cycle;
        // A missing pending request with the same cycle means it already fired.
        if (previous[key] == plan.cycle &&
            (!pending.contains(plan.id) ||
                pendingTitles[plan.id] == plan.title)) {
          continue;
        }
        final now = DateTime.now().toUtc();
        final when = plan.dueAt.toUtc().isAfter(now)
            ? plan.dueAt.toUtc()
            : now.add(const Duration(minutes: 1));
        await _plugin.zonedSchedule(
          id: plan.id,
          title: plan.title,
          body: plan.body,
          payload: plan.plantId,
          scheduledDate: tz.TZDateTime.from(when, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      for (final id in pending.where(_isReminderId)) {
        if (!next.containsKey('$id')) {
          await _plugin.cancel(id: id);
        }
      }
      if (revision == _revision) {
        await prefs.setString(_storageKey, jsonEncode(next));
      }
    });
  }
}
