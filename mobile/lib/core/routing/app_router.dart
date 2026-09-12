import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/main_nav_scaffold.dart';
import '../../features/homework/screens/create_homework_screen.dart';
import '../../features/homework/screens/homework_list_screen.dart';
import '../../features/announcements/screens/announcements_list_screen.dart';
import '../../features/announcements/screens/announcement_detail_screen.dart';
import '../../features/announcements/models/announcement_model.dart';
import '../../features/auth/providers/auth_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever the auth state changes (login/logout/restore).
  final refreshNotifier = ValueNotifier<int>(0);
  ref.listen(authProvider, (previous, next) {
    refreshNotifier.value++;
  });
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loggedIn = auth.isAuthenticated;
      final isOnLogin = state.matchedLocation == '/login';

      if (!loggedIn && !isOnLogin) return '/login';
      if (loggedIn && isOnLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const MainNavScaffold(),
      ),
      GoRoute(
        path: '/dashboard/teacher',
        builder: (context, state) => const MainNavScaffold(),
      ),
      GoRoute(
        path: '/homework',
        builder: (context, state) => const HomeworkListScreen(),
      ),
      GoRoute(
        path: '/homework/create',
        builder: (context, state) => const CreateHomeworkScreen(),
      ),
      GoRoute(
        path: '/announcements',
        builder: (context, state) => const AnnouncementsListScreen(),
      ),
      GoRoute(
        path: '/announcements/detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is AnnouncementModel) {
            return AnnouncementDetailScreen(announcement: extra);
          }
          return const AnnouncementDetailPlaceholderScreen();
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});

/// Shown when /announcements/detail is opened without an announcement object
/// (e.g. deep link). Real entries always pass the model via `extra`.
class AnnouncementDetailPlaceholderScreen extends StatelessWidget {
  const AnnouncementDetailPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: const Center(child: Text('No announcement selected.')),
    );
  }
}
