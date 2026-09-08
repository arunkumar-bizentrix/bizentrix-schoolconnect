import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/main_nav_scaffold.dart';
import '../../features/homework/presentation/create_homework_screen.dart';
import '../../features/announcements/presentation/announcement_detail_screen.dart';
import '../../features/announcements/models/announcement_model.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
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
        path: '/homework/create',
        builder: (context, state) => const CreateHomeworkScreen(),
      ),
      GoRoute(
        path: '/announcements/detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is AnnouncementModel) {
            return AnnouncementDetailScreen(announcement: extra);
          }
          // Default fallback matching mockup 8
          return AnnouncementDetailScreen(
            announcement: AnnouncementModel(
              id: 1,
              title: 'Exam Schedule Released',
              content:
                  'Dear Students and Parents,\n\nThe final exam schedule for Grade 5 - A has been released. Please check the attached timetable and make the necessary preparations.\n\nBest regards,\nSchool Administration',
              priority: 'URGENT',
              audienceType: 'CLASS',
              targetClassId: 1,
              targetClassName: 'Grade 5 - A',
              createdByName: 'Priya Sharma (Teacher)',
              publishedAt: DateTime.now().subtract(const Duration(hours: 4)),
              attachmentUrl: 'https://example.com/exam_schedule.pdf',
            ),
          );
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
