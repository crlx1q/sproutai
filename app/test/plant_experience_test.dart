import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sprout_ai/core/theme.dart';
import 'package:sprout_ai/models/models.dart';
import 'package:sprout_ai/models/weekly_history.dart';
import 'package:sprout_ai/providers/auth_provider.dart';
import 'package:sprout_ai/providers/plants_provider.dart';
import 'package:sprout_ai/screens/home_screen.dart';
import 'package:sprout_ai/screens/onboarding_screen.dart';
import 'package:sprout_ai/screens/plant_screen.dart';
import 'package:sprout_ai/widgets/plant_history.dart';

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => AuthLoggedIn(
    User(
      id: 'u',
      email: 'user@example.test',
      name: 'Алишер',
      plan: 'free',
      role: 'user',
      scansUsed: 1,
    ),
  );
}

class _TestPlants extends PlantsNotifier {
  @override
  Future<List<Plant>> build() async => [fixture()];
}

Plant fixture() => Plant.fromJson({
  '_id': 'sample-plant',
  'name': 'Драцена у большого окна в гостиной',
  'species': 'Dracaena sanderiana',
  'healthScore': 72,
  'healthStatus': 'needs_attention',
  'healthTrend': 'up',
  'previousHealthScore': 55,
  'createdAt': '2026-09-01T09:00:00Z',
  'lastProgressNote':
      'Листья выглядят лучше после пересадки, но сухие края ещё сохраняются.',
  'needsWater': false,
  'needsFertilizer': true,
  'needsCheckup': true,
  'wateringDueAt': '2026-11-01T09:00:00Z',
  'fertilizingDueAt': '2026-10-01T09:00:00Z',
  'checkupDueAt': '2026-10-08T09:00:00Z',
  'care': {
    'light': 'Яркий рассеянный свет возле восточного окна без прямого солнца',
    'temperature': '18–24 °C',
  },
});

void main() {
  test('all dark text theme roles contrast with their surface', () {
    final theme = AppTheme.dark();
    final background = theme.colorScheme.surface.computeLuminance();
    for (final style in [
      theme.textTheme.bodySmall,
      theme.textTheme.titleSmall,
      theme.textTheme.labelMedium,
      theme.textTheme.displaySmall,
    ]) {
      expect(
        (style!.color!.computeLuminance() + .05) / (background + .05),
        greaterThan(4.5),
      );
    }
  });

  testWidgets(
    'onboarding remains scrollable on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const OnboardingScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Дальше'), findsOneWidget);
    },
  );
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'WorkSans',
    )..addFont(rootBundle.load('assets/fonts/WorkSans.ttf'))).load();
    await (FontLoader(
      'Literata',
    )..addFont(rootBundle.load('assets/fonts/Literata.ttf'))).load();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'plant care actions and long text fit ${dark ? 'dark' : 'light'} large type',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final plant = fixture();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              plantDetailsProvider(plant.id).overrideWith(
                (_) async => PlantDetails(
                  plant: plant,
                  journal: const [],
                  reminders: const [],
                ),
              ),
              scanQuotaProvider.overrideWith(
                (_) async =>
                    ScanQuota(plan: 'free', limit: 5, used: 1, remaining: 4),
              ),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
              home: PlantScreen(plantId: plant.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Удобрил(а)'),
          320,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Удобрил(а)'), findsOneWidget);
        expect(find.text('Не сейчас · завтра'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Добавить фото или заметку'),
          320,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'home shows fertilizer and photo tasks even when everything is watered',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_SignedIn.new),
            plantsProvider.overrideWith(_TestPlants.new),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Подкормить · Обновить фото'), findsOneWidget);
      expect(find.text('Все политы!'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekly gaps render in chronological order without inventing photos',
    (tester) async {
      final plant = fixture();
      final now = DateTime.utc(2026, 9, 24, 9);
      final weeks = buildWeeklyHistory(plant, const [], now: now);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: WeeklyPlantHistory(weeks: weeks, journal: const []),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ждём фото'), findsOneWidget);
      expect(find.text('Фото пропущено'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  // Optional output for visual inspection; never required for test correctness.
  testWidgets('render plant status preview', (tester) async {
    final output = Platform.environment['SPROUT_PREVIEW_DIR'];
    if (output == null) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final plant = fixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plantDetailsProvider(plant.id).overrideWith(
            (_) async => PlantDetails(
              plant: plant,
              journal: const [],
              reminders: const [],
            ),
          ),
          scanQuotaProvider.overrideWith(
            (_) async =>
                ScanQuota(plan: 'free', limit: 5, used: 1, remaining: 4),
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: PlantScreen(plantId: plant.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -360));
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(output);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/plant-status-dark.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
