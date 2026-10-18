import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sprout_ai/models/models.dart';
import 'package:sprout_ai/services/notifications.dart';
import 'package:sprout_ai/services/push_service.dart';

Plant plant(
  String id, {
  Map<String, bool> enabled = const {},
  DateTime? due,
  String name = 'Фикус',
}) => Plant.fromJson({
  '_id': id,
  'name': name,
  'care': <String, dynamic>{},
  'wateringDueAt': (due ?? DateTime.utc(2026, 10, 20)).toIso8601String(),
  'fertilizingDueAt': DateTime.utc(2026, 10, 21).toIso8601String(),
  'checkupDueAt': DateTime.utc(2026, 10, 22).toIso8601String(),
  'reminderEnabled': enabled,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'FCM replaces local reminders only after the current token is confirmed',
    () {
      bool remote({
        String? token = 'new-token',
        String? registeredToken,
        bool? enabled,
      }) => shouldUseServerReminders(
        firebaseReady: true,
        hasPermission: true,
        token: token,
        registeredToken: registeredToken,
        serverPushEnabled: enabled,
      );
      expect(
        remote(),
        isFalse,
        reason: 'A failed first POST/token must retain local reminders',
      );
      expect(
        remote(registeredToken: 'old-token', enabled: true),
        isFalse,
        reason: 'A rotated token is not registered until its POST succeeds',
      );
      expect(
        remote(registeredToken: 'new-token', enabled: true),
        isTrue,
        reason:
            'A confirmed token remains usable during a later transient POST failure',
      );
      expect(remote(registeredToken: 'new-token', enabled: false), isFalse);
      expect(remote(registeredToken: 'new-token'), isFalse);
      expect(remote(token: null, enabled: true), isFalse);
      expect(
        shouldUseServerReminders(
          firebaseReady: false,
          hasPermission: true,
          token: 'new-token',
          registeredToken: 'new-token',
          serverPushEnabled: true,
        ),
        isFalse,
      );
      expect(
        shouldUseServerReminders(
          firebaseReady: true,
          hasPermission: false,
          token: 'new-token',
          registeredToken: 'new-token',
          serverPushEnabled: true,
        ),
        isFalse,
      );
    },
  );

  test(
    'same-name plants and reminder types keep separate stable notification IDs',
    () {
      final first = plant('aaaaaaaaaaaaaaaaaaaaaaaa');
      final second = plant('bbbbbbbbbbbbbbbbbbbbbbbb');
      final plans = planPlantReminders([first, second]);
      expect(plans, hasLength(6));
      expect(plans.map((entry) => entry.id).toSet(), hasLength(6));
      final reversed = planPlantReminders([second, first]);
      expect(
        plans.map((entry) => entry.id).toSet(),
        reversed.map((entry) => entry.id).toSet(),
      );
    },
  );

  test(
    'local fallback honors per-type opt-out and schedules timezone-equivalent instants',
    () {
      final plans = planPlantReminders([
        plant(
          'aaaaaaaaaaaaaaaaaaaaaaaa',
          enabled: {'watering': false, 'checkup': false},
        ),
      ]);
      expect(plans.map((entry) => entry.type), ['fertilizing']);
      final a = PlantReminder(
        'one',
        'watering',
        'Фикус',
        DateTime.parse('2026-10-20T12:00:00+05:00'),
      );
      final b = PlantReminder(
        'one',
        'watering',
        'Фикус',
        DateTime.parse('2026-10-20T07:00:00Z'),
      );
      expect(a.cycle, b.cycle);
    },
  );

  test('pending notification cap keeps the earliest 60 reminders', () {
    final plans = planPlantReminders(
      List.generate(
        30,
        (index) => plant('plant$index', due: DateTime.utc(2026, 10, 1 + index)),
      ),
    );
    expect(plans, hasLength(60));
    for (var index = 1; index < plans.length; index++) {
      expect(plans[index].dueAt.isBefore(plans[index - 1].dueAt), isFalse);
    }
  });

  test(
    'schedule reload preserves delivered cycles, reschedules new due dates and cancels disabled types',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final pending = <int, Map<String, dynamic>>{};
      var schedules = 0;
      var permissionRequests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'initialize':
                return true;
              case 'createNotificationChannel':
                return null;
              case 'getNotificationAppLaunchDetails':
                return {'notificationLaunchedApp': false};
              case 'requestNotificationsPermission':
                permissionRequests++;
                return true;
              case 'pendingNotificationRequests':
                return pending.entries
                    .map(
                      (entry) => {
                        'id': entry.key,
                        'title': entry.value['title'],
                        'body': entry.value['body'],
                        'payload': entry.value['payload'],
                      },
                    )
                    .toList();
              case 'zonedSchedule':
                schedules++;
                final args = Map<String, dynamic>.from(call.arguments as Map);
                pending[args['id'] as int] = args;
                return null;
              case 'cancel':
                pending.remove((call.arguments as Map)['id']);
                return null;
              case 'cancelAll':
                pending.clear();
                return null;
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = NotificationService.instance;
      await service.init();
      expect(
        permissionRequests,
        0,
        reason: 'Permissions belong after login, not app startup',
      );
      final first = plant(
        'aaaaaaaaaaaaaaaaaaaaaaaa',
        enabled: {'fertilizing': false, 'checkup': false},
        due: DateTime.utc(2020),
      );
      await service.syncWateringReminders([first]);
      expect(schedules, 1);
      await service.syncWateringReminders([first]);
      expect(schedules, 1);
      pending.clear(); // Simulate the OS delivering the overdue reminder.
      await service.syncWateringReminders([first]);
      expect(
        schedules,
        1,
        reason: 'Reload must not re-arm an already delivered care cycle',
      );
      final later = plant(
        first.id,
        enabled: {'fertilizing': false, 'checkup': false},
        due: DateTime.utc(2020, 2),
      );
      await service.syncWateringReminders([later]);
      expect(schedules, 2);
      expect(pending, hasLength(1));
      await service.syncWateringReminders([
        plant(
          first.id,
          name: 'Фикус на кухне',
          enabled: {'fertilizing': false, 'checkup': false},
          due: DateTime.utc(2020, 2),
        ),
      ]);
      expect(schedules, 3);
      expect(pending.values.single['title'], contains('Фикус на кухне'));
      await service.syncWateringReminders([
        plant(
          first.id,
          enabled: {'watering': false, 'fertilizing': false, 'checkup': false},
        ),
      ]);
      expect(pending, isEmpty);
      await service.cancelAll();
    },
  );
}
