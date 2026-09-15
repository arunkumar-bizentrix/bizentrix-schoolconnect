import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/routing/app_router.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/staff_model.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';
import 'package:school_connect/features/people/providers/people_provider.dart';
import 'package:school_connect/features/people/screens/people_screen.dart';

class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    Object body = {'count': 0, 'next': null, 'previous': null, 'results': []};
    var code = 200;
    if (options.path.endsWith('/auth/change-password/')) {
      final data = options.data as Map;
      if (data['current_password'] != 'Temp-1234') {
        code = 400;
        body = {'current_password': ['The current password is not correct.']};
      } else {
        body = {
          'access': 'new-access',
          'refresh': 'new-refresh',
          'user': {'id': 5, 'email': '', 'full_name': 'Ravi Kumar', 'role': 'PARENT', 'must_change_password': false},
        };
      }
    }
    return ResponseBody.fromString(jsonEncode(body), code, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

class _Auth extends AuthNotifier {
  _Auth(ApiClient client, TokenStorage storage, {required bool mustChange})
      : super(apiClient: client, tokenStorage: storage) {
    state = AuthState(
      user: UserModel(id: '5', email: '', fullName: 'Ravi Kumar', role: UserRole.parent, mustChangePassword: mustChange),
    );
  }

  @override
  Future<bool> restoreSession() async => true;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ({ProviderContainer container, _Server server}) setUpApp({required bool mustChange}) {
    final storage = TokenStorage(const FlutterSecureStorage());
    final client = ApiClient(tokenStorage: storage);
    final server = _Server();
    client.dio.httpClientAdapter = server;
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((ref) => _Auth(client, storage, mustChange: mustChange)),
    ]);
    addTearDown(container.dispose);
    return (container: container, server: server);
  }

  Future<void> pumpRouter(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(400 * 3, 860 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: container.read(appRouterProvider)),
    ));
    await tester.pumpAndSettle();
  }

  test('the profile flag is read from the API', () {
    expect(UserModel.fromJson({'id': 1, 'role': 'TEACHER', 'must_change_password': true}).mustChangePassword, isTrue);
    expect(UserModel.fromJson({'id': 1, 'role': 'TEACHER'}).mustChangePassword, isFalse);
  });

  testWidgets('a temporary password lands on "Choose your password" with no way around it', (tester) async {
    final (:container, server: _) = setUpApp(mustChange: true);
    await pumpRouter(tester, container);

    expect(find.text('Choose your password'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);

    container.read(appRouterProvider).go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('Choose your password'), findsOneWidget, reason: 'the router sends them back');
  });

  testWidgets('choosing a password unlocks the app', (tester) async {
    final (:container, :server) = setUpApp(mustChange: true);
    await pumpRouter(tester, container);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Temp-1234');
    await tester.enterText(fields.at(1), 'Mango-Tree-2026');
    await tester.enterText(fields.at(2), 'Mango-Tree-2026');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final call = server.requests.firstWhere((r) => r.path.endsWith('/auth/change-password/'));
    expect(call.data, {'current_password': 'Temp-1234', 'new_password': 'Mango-Tree-2026'});
    expect(container.read(authProvider).user!.mustChangePassword, isFalse);
    // Let the confirmation snackbar and the move to the dashboard finish.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the form catches a mismatch and all-number passwords before sending', (tester) async {
    final (:container, :server) = setUpApp(mustChange: true);
    await pumpRouter(tester, container);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Temp-1234');
    await tester.enterText(fields.at(1), '1234567890');
    await tester.enterText(fields.at(2), '0987654321');
    await tester.tap(find.text('Save password'));
    await tester.pump();

    expect(find.text('Use letters as well as numbers'), findsOneWidget);
    expect(find.text('The passwords do not match'), findsOneWidget);
    expect(server.requests.where((r) => r.path.endsWith('/auth/change-password/')), isEmpty);
  });

  testWidgets('a wrong temporary password shows the server reason', (tester) async {
    final (:container, server: _) = setUpApp(mustChange: true);
    await pumpRouter(tester, container);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'wrong-password');
    await tester.enterText(fields.at(1), 'Mango-Tree-2026');
    await tester.enterText(fields.at(2), 'Mango-Tree-2026');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(find.text('The current password is not correct.'), findsOneWidget);
    expect(container.read(authProvider).user!.mustChangePassword, isTrue);
  });

  group('login details dialog', () {
    const person = StaffModel(id: 9, fullName: 'Priya Sharma', phoneNumber: '9876500001', role: 'TEACHER');

    Future<void> open(WidgetTester tester, IssuedLogin issued) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLoginDetails(context, issued: issued, isNew: true),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('sent by SMS: says so and shows no password', (tester) async {
      await open(tester, IssuedLogin(account: person, sentBySms: true, expiresAt: DateTime(2026, 9, 22)));
      expect(find.textContaining('sent by SMS to 9876500001'), findsOneWidget);
      expect(find.text('Temporary password'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('not sent: warns clearly and shows the password once', (tester) async {
      await open(
        tester,
        const IssuedLogin(
          account: person,
          sentBySms: false,
          temporaryPassword: 'Km7Q-p4Xz',
          smsDetail: 'SMS is not set up (SMS_PROVIDER is empty).',
        ),
      );
      expect(find.textContaining('Not sent by SMS'), findsOneWidget);
      expect(find.textContaining('SMS is not set up'), findsOneWidget);
      expect(find.text('Km7Q-p4Xz'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });
  });
}
