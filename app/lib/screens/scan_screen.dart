import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/plants_provider.dart';
import '../widgets/common.dart';
import 'shell.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  Future<void> _cameraTask = Future<void>.value();
  int _cameraGeneration = 0;
  bool _cameraRequested = false;
  bool _tabActive = false;
  bool _appResumed = true;
  bool _initializing = false;
  bool _capturing = false;
  bool _picking = false;
  bool _showingResult = false;
  GoRouter? _router;
  String? _cameraError;
  FlashMode _flash = FlashMode.off;
  XFile? _preview;
  String? _analysisError;
  bool _analyzing = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _appResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (!identical(router, _router)) {
      _router?.routeInformationProvider.removeListener(_routeChanged);
      _router = router;
      _router?.routeInformationProvider.addListener(_routeChanged);
    }
    _tabActive = (AppTabScope.indexOf(context) ?? 1) == 1;
    _syncCamera();
  }

  void _routeChanged() {
    if (mounted) _syncCamera();
  }

  bool get _cameraNeeded =>
      _tabActive &&
      _appResumed &&
      !_picking &&
      !_analyzing &&
      !_showingResult &&
      _preview == null &&
      (_router == null ||
          _router!.routeInformationProvider.value.uri.path == '/scan');

  /// Serialize release/initialization so rapid tab or lifecycle changes cannot
  /// create two controllers competing for the native camera.
  void _syncCamera({bool retry = false}) {
    final wanted = _cameraNeeded;
    if (_cameraRequested == wanted && !retry) return;
    _cameraRequested = wanted;
    final generation = ++_cameraGeneration;
    _cameraTask = _cameraTask.then((_) async {
      final previous = _camera;
      _camera = null;
      if (mounted) {
        setState(() {
          _initializing = wanted;
          if (wanted) _cameraError = null;
        });
      }
      await _disposeCamera(previous);
      if (!mounted || generation != _cameraGeneration || !wanted) return;

      CameraController? candidate;
      try {
        final cameras = await availableCameras().timeout(
          const Duration(seconds: 15),
        );
        if (!mounted || generation != _cameraGeneration) return;
        if (cameras.isEmpty) {
          throw CameraException('NoCamera', 'Камера не найдена');
        }
        final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
        final controller = CameraController(
          back,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        candidate = controller;
        await controller.initialize().timeout(const Duration(seconds: 20));
        if (!mounted || generation != _cameraGeneration) {
          await _disposeCamera(controller);
          return;
        }
        // Some cameras do not support flash; this must not hide their preview.
        try {
          await controller.setFlashMode(FlashMode.off);
        } on CameraException catch (_) {}
        if (!mounted || generation != _cameraGeneration) {
          await _disposeCamera(controller);
          return;
        }
        setState(() {
          _camera = controller;
          _flash = FlashMode.off;
          _initializing = false;
        });
      } catch (error) {
        if (mounted && generation == _cameraGeneration) {
          setState(() {
            _initializing = false;
            _cameraError = switch (error) {
              CameraException(
                code: 'CameraAccessDenied' ||
                    'CameraAccessDeniedWithoutPrompt' ||
                    'CameraAccessRestricted',
              ) =>
                'Разрешите доступ к камере в настройках приложения.',
              CameraException(code: 'NoCamera') => 'Камера не найдена.',
              _ =>
                'Камера не запустилась. Повторите попытку или выберите фото.',
            };
          });
        }
        await _disposeCamera(candidate);
      }
    });
  }

  Future<void> _disposeCamera(CameraController? controller) async {
    try {
      await controller?.dispose().timeout(const Duration(seconds: 5));
    } catch (_) {
      // A camera disconnected by Android can already be disposed natively.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routeInformationProvider.removeListener(_routeChanged);
    ++_cameraGeneration;
    _pulse.dispose();
    final controller = _camera;
    _camera = null;
    unawaited(_cameraTask.then((_) => _disposeCamera(controller)));
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      if (mounted && identical(controller, _camera)) {
        setState(() => _flash = next);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Этот режим вспышки недоступен')),
        );
      }
    }
  }

  IconData get _flashIcon => switch (_flash) {
    FlashMode.off => Icons.flash_off,
    FlashMode.auto => Icons.flash_auto,
    _ => Icons.flash_on,
  };

  Future<void> _shoot() async {
    final controller = _camera;
    if (controller == null ||
        !controller.value.isInitialized ||
        _analyzing ||
        _capturing ||
        _picking) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (!mounted || !_tabActive || !_appResumed) return;
      // Гасим фонарик после снимка.
      if (_flash == FlashMode.torch) {
        try {
          await controller.setFlashMode(FlashMode.off);
        } on CameraException catch (_) {}
        _flash = FlashMode.off;
      }
      if (!mounted || !_tabActive || !_appResumed) return;
      setState(() => _preview = shot);
      await _analyze(shot);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сделать снимок')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_analyzing || _capturing || _picking) return;
    setState(() => _picking = true);
    _syncCamera();
    try {
      await _cameraTask;
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
      );
      if (!mounted || picked == null) return;
      setState(() => _preview = picked);
      await _analyze(picked);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть фото. Попробуйте ещё раз.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
        _syncCamera();
      }
    }
  }

  Future<void> _analyze(XFile image) async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _analysisError = null;
    });
    _syncCamera();
    try {
      final api = ref.read(apiProvider);
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(image.path, filename: 'scan.jpg'),
      });
      final res = await api.dio.post('/api/scan', data: form);
      final outcome = ScanOutcome.fromJson(res.data as Map<String, dynamic>);
      ref.invalidate(scanQuotaProvider);
      if (mounted) {
        setState(() {
          _analyzing = false;
          _preview = null;
        });
        await _showResult(outcome);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _analysisError = apiErrorMessage(e);
        });
      }
    } finally {
      if (mounted) _syncCamera();
    }
  }

  Future<void> _showResult(ScanOutcome outcome) async {
    _showingResult = true;
    _syncCamera();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ScanResultSheet(outcome: outcome),
    );
    if (mounted) {
      _showingResult = false;
      _syncCamera();
    }
  }

  Future<void> _openHistory() async {
    _showingResult = true;
    _syncCamera();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.7,
        child: Consumer(
          builder: (context, ref, _) {
            final plants = ref.watch(plantsProvider);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    'История и повторное фото',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Expanded(
                  child: plants.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              apiErrorMessage(e),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: () => ref.invalidate(plantsProvider),
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Добавьте растение после сканирования. Здесь можно будет открыть его фотографии и сделать повторный снимок.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final plant = items[index];
                              return ListTile(
                                leading: PlantImage(
                                  url: plant.photoUrl,
                                  width: 48,
                                  height: 48,
                                ),
                                title: Text(plant.name),
                                subtitle: Text(
                                  plant.species.isEmpty
                                      ? 'Фото и наблюдения'
                                      : plant.species,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  this.context.push('/plant/${plant.id}');
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (mounted) {
      _showingResult = false;
      _syncCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quota = ref.watch(scanQuotaProvider);
    final ready =
        _camera?.value.isInitialized == true &&
        !_initializing &&
        !_analyzing &&
        !_capturing &&
        !_picking;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Row(
                      children: [
                        const SizedBox(width: 44),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/logo.png',
                                width: 24,
                                height: 24,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'PlantDoctor AI',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _RoundButton(
                          icon: _flashIcon,
                          tooltip: 'Вспышка',
                          onTap: ready ? _toggleFlash : null,
                          size: 44,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: (constraints.maxHeight - 320).clamp(240.0, 600.0),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildViewport(),
                                IgnorePointer(
                                  child: AnimatedBuilder(
                                    animation: _pulse,
                                    builder: (context, _) => CustomPaint(
                                      painter: _ViewfinderPainter(
                                        opacity: 0.5 + _pulse.value * 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_analyzing)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 34,
                                          height: 34,
                                          child: CircularProgressIndicator(
                                            color: AppColors.secondaryContainer,
                                            strokeWidth: 3,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'ИДЁТ АНАЛИЗ…',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: Colors.white,
                                                letterSpacing: 2,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_analysisError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                      child: Column(
                        children: [
                          Text(
                            _analysisError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.secondaryContainer,
                                ),
                                onPressed: _preview == null
                                    ? null
                                    : () => _analyze(_preview!),
                                child: const Text('Повторить анализ'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.secondaryContainer,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _preview = null;
                                    _analysisError = null;
                                  });
                                  _syncCamera();
                                },
                                child: const Text('Переснять'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 17,
                          color: AppColors.primaryFixedDim,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Наведите на лист или цветок для лучшего результата',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.primaryFixedDim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  quota.maybeWhen(
                    data: (q) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        q.isUnlimited
                            ? 'Pro: безлимитные сканы ✨'
                            : 'Осталось сканов в этом месяце: ${q.remaining}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primaryFixedDim,
                        ),
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
                    child: Row(
                      children: [
                        _RoundButton(
                          icon: Icons.photo_library_outlined,
                          tooltip: 'Выбрать фото',
                          onTap: _analyzing || _capturing || _picking
                              ? null
                              : _pickFromGallery,
                        ),
                        Expanded(
                          child: Center(
                            child: Semantics(
                              label: 'Сфотографировать растение',
                              button: true,
                              enabled: ready,
                              child: GestureDetector(
                                onTap: ready ? _shoot : null,
                                child: Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ready
                                        ? AppColors.secondaryContainer
                                        : AppColors.secondaryContainer
                                              .withValues(alpha: 0.45),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                      width: 5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.center_focus_weak,
                                    size: 34,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _RoundButton(
                          icon: Icons.history,
                          tooltip: 'История и повторное фото',
                          onTap: _analyzing || _capturing || _picking
                              ? null
                              : _openHistory,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewport() {
    // Снимок-превью на время анализа.
    if (_preview != null) {
      return Image.file(File(_preview!.path), fit: BoxFit.cover);
    }
    if (_cameraError != null) {
      return Container(
        color: AppColors.primaryContainer,
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.no_photography_outlined,
                    size: 44,
                    color: AppColors.onPrimaryContainer,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _cameraError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.secondaryContainer),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => _syncCamera(retry: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: AppColors.primaryContainer,
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.onPrimaryContainer,
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    // Квадратный кроп живого превью.
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        // previewSize приходит в landscape-ориентации.
        width: size.height,
        height: size.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    this.onTap,
    this.size = 52,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          child: Icon(
            icon,
            color: onTap == null ? Colors.white38 : Colors.white,
            size: size * 0.44,
          ),
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.secondaryContainer.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const corner = 34.0;
    const inset = 14.0;
    final w = size.width;
    final h = size.height;

    void arc(Offset start, Offset mid, Offset end) {
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }

    arc(
      const Offset(inset + corner, inset),
      const Offset(inset, inset),
      const Offset(inset, inset + corner),
    );
    arc(
      Offset(w - inset - corner, inset),
      Offset(w - inset, inset),
      Offset(w - inset, inset + corner),
    );
    arc(
      Offset(inset, h - inset - corner),
      Offset(inset, h - inset),
      Offset(inset + corner, h - inset),
    );
    arc(
      Offset(w - inset - corner, h - inset),
      Offset(w - inset, h - inset),
      Offset(w - inset, h - inset - corner),
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

class _ScanResultSheet extends ConsumerStatefulWidget {
  const _ScanResultSheet({required this.outcome});

  final ScanOutcome outcome;

  @override
  ConsumerState<_ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<_ScanResultSheet> {
  bool _adding = false;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.outcome.commonName.isEmpty
          ? 'Новое растение'
          : widget.outcome.commonName,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addToJungle() async {
    if (_adding || !_formKey.currentState!.validate()) return;
    final o = widget.outcome;
    final savedName = _name.text.trim();
    setState(() => _adding = true);
    try {
      final api = ref.read(apiProvider);
      await api.dio.post(
        '/api/plants',
        data: {
          'name': savedName,
          // Photo, diagnosis and care come from the owned server scan. Sending
          // its AI care as manual values would freeze future recommendations.
          'scanId': o.scanId,
        },
      );
      try {
        await ref.read(plantsProvider.notifier).reload();
      } catch (_) {
        // Saving succeeded; a failed refresh must not invite a duplicate plant.
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        Navigator.pop(context);
        router.go('/home');
        messenger.showSnackBar(
          SnackBar(content: Text('«$savedName» в саду 🌿')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = widget.outcome;

    if (!o.isPlant) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 52, color: AppColors.outline),
              const SizedBox(height: 16),
              Text(
                'Растение не найдено',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Попробуйте другой ракурс: лист или цветок крупным планом.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Сделать другое фото'),
              ),
            ],
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 36),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(o.commonName, style: theme.textTheme.headlineLarge),
          Text(
            o.species,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              boxShadow: softShadow(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'ЗДОРОВЬЕ',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${o.healthScore}/100',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (o.healthScore / 100).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: scheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation(
                      o.healthScore >= 70
                          ? AppColors.secondary
                          : o.healthScore >= 45
                          ? const Color(0xFFB77B1F)
                          : AppColors.terracotta,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: o.isHealthy
                  ? scheme.secondaryContainer
                  : scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      o.isHealthy
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 19,
                      color: o.isHealthy
                          ? scheme.onSecondaryContainer
                          : scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        o.diagnosisTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: o.isHealthy
                              ? scheme.onSecondaryContainer
                              : scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    Text(
                      '${(o.confidence * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: o.isHealthy
                            ? scheme.onSecondaryContainer
                            : scheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  o.diagnosisDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: o.isHealthy
                        ? scheme.onSecondaryContainer
                        : scheme.onTertiaryContainer,
                  ),
                ),
                if (o.progressNote.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Динамика: ${o.progressNote}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: o.isHealthy
                          ? scheme.onSecondaryContainer
                          : scheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (o.treatmentPlan.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('План лечения', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 10),
            ...o.treatmentPlan.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${e.key + 1}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(e.value, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text('Рекомендации по уходу', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          _CareRow(
            icon: Icons.water_drop_outlined,
            label: 'Полив',
            value: o.careAdvice.watering,
          ),
          _CareRow(
            icon: Icons.wb_sunny_outlined,
            label: 'Свет',
            value: o.careAdvice.light,
          ),
          _CareRow(
            icon: Icons.science_outlined,
            label: 'Удобрение',
            value: o.careAdvice.fertilizer,
          ),
          _CareRow(
            icon: Icons.thermostat_outlined,
            label: 'Температура',
            value: o.careAdvice.temperature,
          ),
          const SizedBox(height: 26),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _name,
              enabled: !_adding,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Имя в моём саду',
                hintText: 'Например, «Бамбук у окна»',
                helperText: 'Личное имя поможет отличать растения одного вида.',
                helperMaxLines: 3,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Дайте растению имя'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _adding ? null : _addToJungle,
            icon: _adding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add),
            label: const Text('Добавить в мой сад'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _adding ? null : () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _CareRow extends StatelessWidget {
  const _CareRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.sage,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
