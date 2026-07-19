import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    (
      icon: Icons.center_focus_weak,
      title: 'Одно фото — полный диагноз',
      text:
          'Наведите камеру на растение: ИИ определит вид, найдёт болезни и дефициты питания за секунды.',
    ),
    (
      icon: Icons.water_drop_outlined,
      title: 'Уход без забытых поливов',
      text:
          'Персональные расписания полива и подкормки для каждого растения — с напоминаниями точно в срок.',
    ),
    (
      icon: Icons.auto_graph,
      title: 'Дневник «до/после»',
      text:
          'Фиксируйте лечение фотографиями. Повторный скан покажет, отступает болезнь или пора менять план.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/logo.png', width: 30, height: 30),
                  ),
                  const SizedBox(width: 8),
                  Text('Sprout AI', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go('/auth'),
                    child: const Text('Пропустить'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final slide = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            color: AppColors.secondaryContainer,
                            shape: BoxShape.circle,
                            boxShadow: softShadow(),
                          ),
                          child: Icon(slide.icon, size: 80, color: AppColors.primary),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          slide.title,
                          style: theme.textTheme.headlineLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide.text,
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? AppColors.primary : AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: FilledButton(
                onPressed: () {
                  if (_page < _slides.length - 1) {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    context.go('/auth');
                  }
                },
                child: Text(_page < _slides.length - 1 ? 'Дальше' : 'Начать'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
