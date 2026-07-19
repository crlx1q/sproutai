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

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  Future<void>? _cameraInit;
  String? _cameraError;
  FlashMode _flash = FlashMode.off;
  XFile? _preview;
  bool _analyzing = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'Камера не найдена');
        return;
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
      _camera = controller;
      _cameraInit = controller.initialize().then((_) async {
        await controller.setFlashMode(_flash);
        if (mounted) setState(() {});
      });
      setState(() {});
    } catch (e) {
      setState(() => _cameraError = 'Нет доступа к камере');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _camera?.dispose();
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
      setState(() => _flash = next);
    } catch (_) {}
  }

  IconData get _flashIcon => switch (_flash) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        _ => Icons.flash_on,
      };

  Future<void> _shoot() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || _analyzing) {
      return;
    }
    try {
      final shot = await controller.takePicture();
      // Гасим фонарик после снимка.
      if (_flash == FlashMode.torch) {
        await controller.setFlashMode(FlashMode.off);
        _flash = FlashMode.off;
      }
      setState(() => _preview = shot);
      await _analyze(shot);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сделать снимок')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_analyzing) return;
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 88);
    if (picked == null) return;
    setState(() => _preview = picked);
    await _analyze(picked);
  }

  Future<void> _analyze(XFile image) async {
    setState(() => _analyzing = true);
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
        _showResult(outcome);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _preview = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  void _showResult(ScanOutcome outcome) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ScanResultSheet(outcome: outcome),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quota = ref.watch(scanQuotaProvider);

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
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
                        Image.asset('assets/logo.png', width: 24, height: 24),
                        const SizedBox(width: 8),
                        Text(
                          'PlantDoctor AI',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  _RoundButton(icon: _flashIcon, onTap: _toggleFlash, size: 44),
                ],
              ),
            ),
            Expanded(
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
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) => CustomPaint(
                              painter: _ViewfinderPainter(
                                opacity: 0.5 + _pulse.value * 0.5,
                              ),
                            ),
                          ),
                          if (_analyzing)
                            Container(
                              color: Colors.black.withValues(alpha: 0.45),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                                    style: theme.textTheme.labelLarge?.copyWith(
                                        color: Colors.white, letterSpacing: 2),
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
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline,
                      size: 17, color: AppColors.primaryFixedDim),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Наведите на лист или цветок для лучшего результата',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.primaryFixedDim),
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
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.primaryFixedDim),
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
                    onTap: _pickFromGallery,
                  ),
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: _analyzing ? null : _shoot,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.secondaryContainer,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 5,
                            ),
                          ),
                          child: const Icon(Icons.center_focus_weak,
                              size: 34, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  _RoundButton(
                    icon: Icons.history,
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'История сканов доступна в карточках растений')),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 44, color: AppColors.onPrimaryContainer),
              const SizedBox(height: 10),
              Text(_cameraError!,
                  style: const TextStyle(color: AppColors.onPrimaryContainer)),
            ],
          ),
        ),
      );
    }
    final controller = _camera;
    if (controller == null) {
      return Container(color: AppColors.primaryContainer);
    }
    return FutureBuilder<void>(
      future: _cameraInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return Container(
            color: AppColors.primaryContainer,
            child: const Center(
              child: CircularProgressIndicator(
                  color: AppColors.onPrimaryContainer, strokeWidth: 2.5),
            ),
          );
        }
        // Квадратный кроп живого превью.
        final size = controller.value.previewSize!;
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
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.onTap, this.size = 52});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.44),
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

    arc(const Offset(inset + corner, inset), const Offset(inset, inset),
        const Offset(inset, inset + corner));
    arc(Offset(w - inset - corner, inset), Offset(w - inset, inset),
        Offset(w - inset, inset + corner));
    arc(Offset(inset, h - inset - corner), Offset(inset, h - inset),
        Offset(inset + corner, h - inset));
    arc(Offset(w - inset - corner, h - inset), Offset(w - inset, h - inset),
        Offset(w - inset, h - inset - corner));
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

  Future<void> _addToJungle() async {
    final o = widget.outcome;
    setState(() => _adding = true);
    try {
      final api = ref.read(apiProvider);
      await api.dio.post('/api/plants', data: {
        'name': o.commonName.isNotEmpty ? o.commonName : 'Новое растение',
        'species': o.species,
        'photoUrl': o.imageUrl,
        // Передаём реальный результат скана, чтобы здоровье не сбрасывалось в 90%.
        'healthScore': o.healthScore,
        'isHealthy': o.isHealthy,
        'scanId': o.scanId,
        'diagnosis': {
          'isHealthy': o.isHealthy,
          'title': o.diagnosisTitle,
          'description': o.diagnosisDescription,
          'confidence': o.confidence,
          'treatmentPlan': o.treatmentPlan,
        },
        'care': {
          'wateringIntervalDays': o.careAdvice.wateringIntervalDays,
          'waterAmountMl': o.careAdvice.waterAmountMl,
          'light': o.careAdvice.light,
          'fertilizerIntervalDays': o.careAdvice.fertilizerIntervalDays,
          'temperature': o.careAdvice.temperature,
        },
      });
      await ref.read(plantsProvider.notifier).reload();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${o.commonName}» в саду 🌿')),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.outcome;

    if (!o.isPlant) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 52, color: AppColors.outline),
            const SizedBox(height: 16),
            Text('Растение не найдено', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Попробуйте другой ракурс: лист или цветок крупным планом.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
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
          Text(o.species,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: softShadow(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ЗДОРОВЬЕ',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(letterSpacing: 1.2)),
                    Text('${o.healthScore}/100',
                        style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: o.healthScore / 100,
                    minHeight: 10,
                    backgroundColor: AppColors.surfaceContainer,
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
              color: o.isHealthy ? AppColors.mintSoft : AppColors.terracottaContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      o.isHealthy ? Icons.check_circle_outline : Icons.error_outline,
                      size: 19,
                      color: o.isHealthy ? AppColors.secondary : AppColors.terracotta,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        o.diagnosisTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: o.isHealthy
                              ? AppColors.primaryContainer
                              : AppColors.terracotta,
                        ),
                      ),
                    ),
                    Text(
                      '${(o.confidence * 100).round()}%',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(o.diagnosisDescription, style: theme.textTheme.bodyMedium),
                if (o.progressNote.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Динамика: ${o.progressNote}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
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
          _CareRow(icon: Icons.water_drop_outlined, label: 'Полив',
              value: o.careAdvice.watering),
          _CareRow(icon: Icons.wb_sunny_outlined, label: 'Свет',
              value: o.careAdvice.light),
          _CareRow(icon: Icons.science_outlined, label: 'Удобрение',
              value: o.careAdvice.fertilizer),
          _CareRow(icon: Icons.thermostat_outlined, label: 'Температура',
              value: o.careAdvice.temperature),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: _adding ? null : _addToJungle,
            icon: _adding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.add),
            label: const Text('Добавить в мой сад'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _CareRow extends StatelessWidget {
  const _CareRow({required this.icon, required this.label, required this.value});

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
                Text(label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
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
