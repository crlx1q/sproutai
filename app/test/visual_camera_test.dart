import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sprout_ai/core/theme.dart';
import 'package:sprout_ai/core/api.dart';
import 'package:sprout_ai/models/models.dart';
import 'package:sprout_ai/providers/community_provider.dart';
import 'package:sprout_ai/providers/plants_provider.dart';
import 'package:sprout_ai/screens/community_screen.dart';
import 'package:sprout_ai/screens/scan_screen.dart';
import 'package:sprout_ai/screens/shell.dart';

const _cameraChannel = MethodChannel('plugins.flutter.io/camera');

/// Native camera events are faked; no physical camera or server is used.
class _CameraDevice {
  int enumerations = 0;
  int creations = 0;
  final disposed = <int>[];
  bool available = true;
  bool initializeImmediately = true;
  bool denyAccess = false;
  bool flashSupported = true;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'availableCameras':
        enumerations++;
        return available
            ? [
                {'name': 'back', 'lensFacing': 'back', 'sensorOrientation': 90},
              ]
            : <Object>[];
      case 'create':
        if (denyAccess) throw PlatformException(code: 'CameraAccessDenied');
        return {'cameraId': ++creations};
      case 'initialize':
        if (initializeImmediately) {
          initialized((call.arguments as Map)['cameraId'] as int);
        }
        return <String, Object>{};
      case 'setFlashMode':
        if (!flashSupported) throw PlatformException(code: 'FlashNotSupported');
        return null;
      case 'dispose':
        disposed.add((call.arguments as Map)['cameraId'] as int);
        return null;
      default:
        return null;
    }
  }

  void initialized(int cameraId) {
    ServicesBinding.instance.channelBuffers.push(
      'flutter.io/cameraPlugin/camera$cameraId',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('initialized', {
          'previewWidth': 640.0,
          'previewHeight': 480.0,
          'exposureMode': 'auto',
          'exposurePointSupported': false,
          'focusMode': 'auto',
          'focusPointSupported': false,
        }),
      ),
      (_) {},
    );
  }
}

class _Feed extends FeedNotifier {
  @override
  Future<List<Post>> build() async => [
    Post(
      id: 'post',
      authorName: 'Очень длинное имя автора публикации о любимом растении',
      text: 'Мой сад',
      likesCount: 0,
      likedByMe: false,
      commentsCount: 1,
      createdAt: DateTime(2026, 10, 18),
    ),
  ];

  @override
  Future<void> createPost({required String text, MultipartFile? image}) async {
    throw StateError('Connection unavailable');
  }
}

class _NoTokens extends TokenStorage {
  @override
  Future<String?> get accessToken async => null;
}

Future<void> _pumpScanner(WidgetTester tester, ValueNotifier<int> tab) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scanQuotaProvider.overrideWith(
          (ref) async =>
              ScanQuota(plan: 'free', used: 0, limit: 5, remaining: 5),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (_, index, child) =>
              AppTabScope(index: index, child: child!),
          child: const ScanScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans.ttf'))).load();
    await (FontLoader(
      'WorkSans',
    )..addFont(rootBundle.load('assets/fonts/WorkSans.ttf'))).load();
    await (FontLoader(
      'Literata',
    )..addFont(rootBundle.load('assets/fonts/Literata.ttf'))).load();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cameraChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        );
  });

  testWidgets('scanner releases camera off tab and restores it after resume', (
    tester,
  ) async {
    final device = _CameraDevice()..flashSupported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cameraChannel, device.handle);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final tab = ValueNotifier(1);
    addTearDown(tab.dispose);
    await _pumpScanner(tester, tab);
    expect(
      find.byType(CameraPreview),
      findsOneWidget,
      reason: 'Unsupported flash must not prevent camera preview',
    );
    expect(device.creations, 1);

    tab.value = 0;
    await tester.pump();
    await tester.pump();
    expect(device.disposed, [1]);
    expect(find.byType(CameraPreview), findsNothing);

    tab.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(device.creations, 2);
    expect(find.byType(CameraPreview), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump();
    expect(device.disposed, [1, 2]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(device.creations, 3);
    expect(find.byType(CameraPreview), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(device.disposed, [1, 2, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera recovers with no previous controller and exposes retry', (
    tester,
  ) async {
    final device = _CameraDevice()..available = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cameraChannel, device.handle);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final tab = ValueNotifier(1);
    addTearDown(tab.dispose);
    await _pumpScanner(tester, tab);
    expect(find.text('Камера не найдена.'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(device.enumerations, 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    device.available = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(device.enumerations, 3);
    expect(find.byType(CameraPreview), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'backgrounding during initialization disposes the stale controller',
    (tester) async {
      final device = _CameraDevice()..initializeImmediately = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_cameraChannel, device.handle);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final tab = ValueNotifier(1);
      addTearDown(tab.dispose);
      await _pumpScanner(tester, tab);
      expect(device.creations, 1);
      expect(find.byType(CameraPreview), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      device.initialized(1);
      await tester.pump();
      await tester.pump();
      expect(device.disposed, [1]);
      expect(find.byType(CameraPreview), findsNothing);

      device.initializeImmediately = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CameraPreview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(device.disposed, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dark comments sheet stays readable with long names and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dark = AppTheme.dark();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedProvider.overrideWith(_Feed.new),
            commentsProvider('post').overrideWith(
              (ref) async => [
                PostComment(
                  id: 'comment',
                  authorName: 'Автор с длинным именем',
                  text: 'Согласен',
                  createdAt: DateTime(2026, 10, 18),
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const CommunityScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mode_comment_outlined));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, dark.colorScheme.surface);
      final heading = tester.widget<Text>(find.text('Комментарии'));
      expect(heading.style!.color!.computeLuminance(), greaterThan(0.5));
      expect(find.text('Согласен'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed publication keeps the draft open for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [feedProvider.overrideWith(_Feed.new)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CommunityScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Черновик о монстере');
    await tester.ensureVisible(find.text('Опубликовать'));
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();
    expect(find.text('Новый пост'), findsOneWidget);
    expect(find.text('Черновик о монстере'), findsOneWidget);
    expect(find.text('Опубликовать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scan result uses dark surfaces and readable long text at enlarged size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final device = _CameraDevice()..available = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_cameraChannel, device.handle);
      var galleryCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (_) async {
              galleryCalls++;
              return File('assets/logo.png').absolute.path;
            },
          );
      const name = 'Драцена Сандера (Счастливый бамбук) у большого окна';
      const description =
          'Растение выглядит здоровым: стебли ярко-зелёные, '
          'листья упругие без признаков болезни. Продолжайте наблюдать за новым ростом.';
      var requests = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://local.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            expect(options.path, '/api/scan');
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'scanId': 'scan',
                  'imageUrl': '',
                  'result': {
                    'isPlant': true,
                    'commonName': name,
                    'species': 'Dracaena sanderiana',
                    'isHealthy': true,
                    'healthScore': 95,
                    'diagnosis': {
                      'title': 'Здоровое растение',
                      'description': description,
                      'confidence': 0.98,
                    },
                    'treatmentPlan': <String>[],
                    'careAdvice': {
                      'watering':
                          'Поливайте по мере подсыхания верхнего слоя грунта, избегайте застоя воды.',
                      'light':
                          'Яркий рассеянный свет, избегайте прямых солнечных лучей.',
                      'fertilizer':
                          'Соблюдайте рекомендованный интервал подкормки.',
                      'temperature': '18–24 °C',
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final api = ApiClient(_NoTokens(), client: dio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final dark = AppTheme.dark();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiProvider.overrideWithValue(api),
            scanQuotaProvider.overrideWith(
              (_) async =>
                  ScanQuota(plan: 'free', limit: 5, used: 0, remaining: 5),
            ),
          ],
          child: MaterialApp(
            theme: dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const ScanScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.byIcon(Icons.photo_library_outlined));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.photo_library_outlined));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      // Local file metadata runs outside the widget test's fake clock.
      for (var attempt = 0; attempt < 40 && requests == 0; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pump(const Duration(milliseconds: 400));
      // The sheet is inserted after file I/O completes; advance its entrance
      // animation on a subsequent frame before testing real drag hit targets.
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        requests,
        1,
        reason:
            'gallery=$galleryCalls; '
            '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
      );
      expect(find.text(name), findsOneWidget);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, dark.colorScheme.surface);
      final title = tester.widget<Text>(find.text(name));
      expect(title.style!.color, dark.colorScheme.onSurface);
      expect(tester.takeException(), isNull);

      final sheetScroll = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(description),
        200,
        scrollable: sheetScroll,
      );
      final diagnosis = tester.widget<Text>(find.text(description));
      expect(diagnosis.style!.color, dark.colorScheme.onSecondaryContainer);
      final luminanceText = diagnosis.style!.color!.computeLuminance();
      final luminanceBackground = dark.colorScheme.secondaryContainer
          .computeLuminance();
      expect(
        (luminanceText + 0.05) / (luminanceBackground + 0.05),
        greaterThan(4.5),
      );
      await tester.scrollUntilVisible(
        find.byType(TextFormField),
        250,
        scrollable: sheetScroll,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        name,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
