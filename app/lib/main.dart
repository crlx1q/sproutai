import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/add_plant_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/community_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/plant_screen.dart';
import 'screens/pro_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'services/notifications.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  await NotificationService.instance.init();
  try {
    await PushService.instance.init();
  } catch (_) {
    // Без Firebase-конфига приложение продолжает работать без пушей.
  }
  runApp(const ProviderScope(child: SproutApp()));
}

final _routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ValueNotifier(0);
  ref.listen(authProvider, (_, __) => authListenable.value++);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final inAuthFlow = loc == '/auth' || loc == '/onboarding';
      if (auth is AuthLoading) return loc == '/splash' ? null : '/splash';
      if (auth is AuthLoggedOut) {
        if (loc == '/splash') return '/onboarding';
        return inAuthFlow ? null : '/onboarding';
      }
      if (auth is AuthLoggedIn && (loc == '/splash' || inAuthFlow)) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/community', builder: (_, __) => const CommunityScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/plant/:id',
        builder: (_, state) => PlantScreen(plantId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/add-plant', builder: (_, __) => const AddPlantScreen()),
      GoRoute(path: '/pro', builder: (_, __) => const ProScreen()),
    ],
  );
});

class SproutApp extends ConsumerWidget {
  const SproutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Sprout AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(_routerProvider),
    );
  }
}
