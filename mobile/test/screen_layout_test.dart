import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/announcements/models/announcement_model.dart';
import 'package:school_connect/features/announcements/screens/announcement_detail_screen.dart';
import 'package:school_connect/features/announcements/screens/announcements_list_screen.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';
import 'package:school_connect/features/auth/screens/login_screen.dart';
import 'package:school_connect/features/classes/screens/classes_screen.dart';
import 'package:school_connect/features/homework/screens/create_homework_screen.dart';
import 'package:school_connect/features/homework/screens/homework_list_screen.dart';
import 'package:school_connect/features/notifications/screens/notifications_list_screen.dart';
import 'package:school_connect/features/profile/screens/profile_screen.dart';
import 'package:school_connect/features/students/screens/students_screen.dart';

/// Every screen, every role, at the narrowest width we support.
///
/// A RenderFlex overflow is a real user-visible bug (the yellow/black stripe),
/// so these tests fail the build rather than letting one reach a parent's
/// phone. 360dp is the common low-end Android width; the web shell caps the
/// app at 430dp.
class _EmptyAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"count":0,"next":null,"previous":null,"results":[]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(ApiClient client, TokenStorage storage, UserRole role)
      : super(apiClient: client, tokenStorage: storage) {
    state = AuthState(
      user: UserModel(
        id: '1',
        email: 'demo@example.test',
        fullName: 'Priya Sharma',
        role: role,
        schoolName: 'Vivekananda School, Bagalur',
        phoneNumber: '9876543210',
      ),
    );
  }

  @override
  Future<bool> restoreSession() async => true;
}

Widget _wrap(Widget screen, UserRole role) {
  final storage = TokenStorage(const FlutterSecureStorage());
  final client = ApiClient(tokenStorage: storage);
  client.dio.httpClientAdapter = _EmptyAdapter();

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((ref) => _TestAuthNotifier(client, storage, role)),
    ],
    // Several of these are page *bodies* that normally live inside
    // MainNavScaffold's Scaffold, so they need a Material ancestor here too.
    // A minimal GoRouter stands in for the real one: some screens call
    // context.push/go, which asserts without a router above them.
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => Scaffold(body: screen)),
          GoRoute(path: '/login', builder: (_, __) => const SizedBox.shrink()),
          GoRoute(path: '/homework', builder: (_, __) => const SizedBox.shrink()),
          GoRoute(path: '/students', builder: (_, __) => const SizedBox.shrink()),
          GoRoute(path: '/announcements', builder: (_, __) => const SizedBox.shrink()),
        ],
      ),
    ),
  );
}

final _sampleAnnouncement = AnnouncementModel.fromJson({
  'id': 1,
  'title': 'Annual Sports Day at the main school ground',
  'content': 'All students should report by 8:00 AM in full sports uniform.',
  'priority': 'URGENT',
  'audience_type': 'SCHOOL',
  'created_by_name': 'School Administration',
  'published_at': '2026-09-08T09:00:00Z',
});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> expectNoOverflow(
    WidgetTester tester,
    Widget screen,
    UserRole role,
    double width,
  ) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(screen, role));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.takeException(),
      isNull,
      reason: '${screen.runtimeType} overflowed at ${width}dp as $role',
    );
  }

  final Map<String, Widget> screens = <String, Widget>{
    'ClassesScreen': const ClassesScreen(),
    'StudentsScreen': const StudentsScreen(),
    'HomeworkListScreen': const HomeworkListScreen(),
    'AnnouncementsListScreen': const AnnouncementsListScreen(),
    'NotificationsListScreen': const NotificationsListScreen(),
    'ProfileScreen': const ProfileScreen(),
    'CreateHomeworkScreen': const CreateHomeworkScreen(),
    'AnnouncementDetailScreen':
        AnnouncementDetailScreen(announcement: _sampleAnnouncement),
    'LoginScreen': const LoginScreen(),
  };

  /// A heading squeezed to near-zero width wraps one letter per line. That is
  /// not an overflow, so the checks above cannot see it - this measures the
  /// rendered box instead.
  Future<void> expectHeadingReadable(
    WidgetTester tester,
    Widget screen,
    UserRole role,
    double width,
    String heading,
  ) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(screen, role));
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    final finder = find.text(heading);
    if (finder.evaluate().isEmpty) return; // heading not shown for this role
    final size = tester.getSize(finder.first);
    expect(
      size.width,
      greaterThan(60),
      reason: '"$heading" collapsed to ${size.width.toStringAsFixed(1)}dp wide '
          'at ${width}dp as $role - it will render one letter per line',
    );
    expect(
      size.height,
      lessThan(80),
      reason: '"$heading" grew to ${size.height.toStringAsFixed(1)}dp tall '
          'at ${width}dp as $role - it is wrapping vertically',
    );
  }

  final headings = <String, String>{
    'ClassesScreen': 'Classes',
    'StudentsScreen': 'Students',
    'HomeworkListScreen': 'Homework',
    'AnnouncementsListScreen': 'Announcements',
  };

  // 280dp is narrower than any real phone, but the web shell can hand the app
  // a width like this, and that is exactly how the vertical-text bug appeared.
  for (final width in [280.0, 320.0, 360.0, 430.0]) {
    for (final role in [UserRole.admin, UserRole.teacher, UserRole.parent]) {
      headings.forEach((screenName, heading) {
        testWidgets('$screenName heading stays readable at ${width.toInt()}dp as ${role.code}',
            (tester) async {
          await expectHeadingReadable(
              tester, screens[screenName]!, role, width, heading);
        });
      });
    }
  }

  for (final width in [360.0, 430.0]) {
    for (final role in [UserRole.admin, UserRole.teacher, UserRole.parent]) {
      screens.forEach((name, screen) {
        testWidgets('$name fits ${width.toInt()}dp as ${role.code}',
            (tester) async {
          await expectNoOverflow(tester, screen, role, width);
        });
      });
    }
  }
}
