import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';
import 'package:school_connect/features/dashboard/screens/main_nav_scaffold.dart';

/// Answers every list request with an empty page, instantly. Keeps the widget
/// tests free of real sockets and pending timers.
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
        fullName: 'School Admin',
        role: role,
        schoolName: 'Vivekananda School, Bagalur',
      ),
    );
  }

  @override
  Future<bool> restoreSession() async => true;
}

ProviderScope _app(UserRole role) {
  final storage = TokenStorage(const FlutterSecureStorage());
  final client = ApiClient(tokenStorage: storage);
  client.dio.httpClientAdapter = _EmptyAdapter();

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((ref) => _TestAuthNotifier(client, storage, role)),
    ],
    child: const MaterialApp(home: MainNavScaffold()),
  );
}

/// Scopes a label to the bottom navigation bar - the same words also appear
/// inside the pages themselves.
Finder _navItem(String label) => find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// The web build constrains the app to 430 logical pixels wide
  /// (see app.dart). Layout has to survive that width.
  Future<void> pumpAtPhoneWidth(WidgetTester tester, UserRole role) async {
    tester.view.physicalSize = const Size(430 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(role));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('admin shell lays out at 430px with no overflow', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.admin);

    // A RenderFlex overflow is reported as a FlutterError during paint;
    // takeException() returns null when the frame was clean.
    expect(tester.takeException(), isNull);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('admin shell lays out at narrow 360px width with no overflow', (tester) async {
    FlutterErrorDetails? errorDetails;
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      errorDetails = details;
      oldHandler?.call(details);
    };
    try {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(UserRole.admin));
      await tester.pump(const Duration(milliseconds: 100));

      if (errorDetails != null && errorDetails!.informationCollector != null) {
        for (final node in errorDetails!.informationCollector!()) {
          debugPrint('COLLECTOR: ${node.toDescription()}');
        }
      }
      expect(tester.takeException(), isNull);
      expect(find.text(AppConstants.schoolName), findsOneWidget);
    } finally {
      FlutterError.onError = oldHandler;
    }
  });

  testWidgets('admin stat cards switch tabs when tapped', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.admin);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainNavScaffold)),
    );

    // Tap Total Students stat card -> should navigate to tab 2 (Students)
    await tester.tap(find.text('Total Students'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(bottomNavIndexProvider), 2);

    // Switch back to Home (tab 0)
    await tester.tap(_navItem('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(bottomNavIndexProvider), 0);

    // Tap Active Classes stat card -> should navigate to tab 1 (Classes)
    await tester.tap(find.text('Active Classes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(bottomNavIndexProvider), 1);
  });

  testWidgets('tapping a bottom nav item switches the visible page', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.admin);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainNavScaffold)),
    );
    expect(container.read(bottomNavIndexProvider), 0);

    await tester.tap(_navItem('Students'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(bottomNavIndexProvider),
      2,
      reason: 'tapping the third tab should select index 2',
    );

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 2, reason: 'IndexedStack should follow the selected tab');
  });

  testWidgets('every admin tab is reachable', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.admin);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainNavScaffold)),
    );

    for (final entry in {'Classes': 1, 'Students': 2, 'Homework': 3, 'Notices': 4, 'Profile': 5}.entries) {
      await tester.tap(_navItem(entry.key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(bottomNavIndexProvider), entry.value,
          reason: 'tab "${entry.key}" should select index ${entry.value}');
    }
  });

  testWidgets('teacher shell lays out at 430px with no overflow', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.teacher);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent shell lays out at 430px with no overflow', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.parent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher tabs are reachable', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.teacher);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainNavScaffold)),
    );

    for (final entry in {'Classes': 1, 'Homework': 2, 'Notices': 3, 'Profile': 4}.entries) {
      await tester.tap(_navItem(entry.key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(bottomNavIndexProvider), entry.value,
          reason: 'tab "${entry.key}" should select index ${entry.value}');
    }
  });

  testWidgets('parent tabs are reachable', (tester) async {
    await pumpAtPhoneWidth(tester, UserRole.parent);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainNavScaffold)),
    );

    for (final entry in {'Homework': 1, 'Notices': 2, 'Alerts': 3, 'Profile': 4}.entries) {
      await tester.tap(_navItem(entry.key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(bottomNavIndexProvider), entry.value,
          reason: 'tab "${entry.key}" should select index ${entry.value}');
    }
  });
}
