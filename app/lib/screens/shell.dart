import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

/// Indexed navigation keeps screens mounted. Camera resources must follow the
/// selected branch instead of the lifetime of the scanner widget.
class AppTabScope extends InheritedWidget {
  const AppTabScope({super.key, required this.index, required super.child});

  final int index;

  static int? indexOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTabScope>()?.index;

  @override
  bool updateShouldNotify(AppTabScope oldWidget) => index != oldWidget.index;
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppTabScope(index: shell.currentIndex, child: shell),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurfaceContainer
              : Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Сад',
                    active: shell.currentIndex == 0,
                    onTap: () => shell.goBranch(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.center_focus_weak,
                    activeIcon: Icons.center_focus_strong,
                    label: 'Сканер',
                    active: shell.currentIndex == 1,
                    onTap: () => shell.goBranch(1),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Общение',
                    active: shell.currentIndex == 2,
                    onTap: () => shell.goBranch(2),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: 'Профиль',
                    active: shell.currentIndex == 3,
                    onTap: () => shell.goBranch(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = scheme.onSecondaryContainer;
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          decoration: BoxDecoration(
            color: active ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? activeIcon : icon,
                size: 24,
                color: active ? activeColor : scheme.outline,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? activeColor : scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
