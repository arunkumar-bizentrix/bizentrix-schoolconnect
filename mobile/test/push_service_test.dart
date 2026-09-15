import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/push/push_service.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';

/// Records every request so a test can assert what did - and did not - go out.
class _RecordingAdapter implements HttpClientAdapter {
  final List<String> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    return ResponseBody.fromString(
      '{"registered":true,"push_enabled":false}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _ScriptedAuthNotifier extends AuthNotifier {
  _ScriptedAuthNotifier(ApiClient client, TokenStorage storage, Ref ref)
      : super(apiClient: client, tokenStorage: storage, ref: ref);

  @override
  Future<bool> restoreSession() async => true;

  void signIn() {
    state = const AuthState(
      user: UserModel(
        id: '1',
        email: 'parent@example.test',
        fullName: 'Parent',
        role: UserRole.parent,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late _RecordingAdapter adapter;
  late ProviderContainer container;
  late TokenStorage storage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    adapter = _RecordingAdapter();
    storage = TokenStorage(const FlutterSecureStorage());
    final client = ApiClient(tokenStorage: storage);
    client.dio.httpClientAdapter = adapter;

    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    addTearDown(() => PushService.debugAvailable = false);
  });

  group('when push is not configured', () {
    test('registering is a no-op rather than an error', () async {
      PushService.debugAvailable = false;

      await container.read(pushServiceProvider).registerDevice();

      expect(adapter.calls, isEmpty);
    });

    test('the notification streams stay silent instead of throwing', () async {
      PushService.debugAvailable = false;
      final push = container.read(pushServiceProvider);

      expect(await push.onForegroundMessage.isEmpty, isTrue);
      expect(await push.onNotificationTapped.isEmpty, isTrue);
    });
  });

  test('a device Firebase cannot serve does not break sign-in', () async {
    // No Firebase app exists in a test, so asking for a token throws. Sign-in
    // must survive that: notifications are optional, getting into the app is
    // not.
    PushService.debugAvailable = true;

    await expectLater(
      container.read(pushServiceProvider).registerDevice(),
      completes,
    );
    expect(adapter.calls, isEmpty);
  });

  test('signing out still completes when there is no device to release',
      () async {
    PushService.debugAvailable = false;
    await storage.saveTokens(accessToken: 'token-value');

    final auth = container.read(
      StateNotifierProvider<AuthNotifier, AuthState>(
        (ref) => _ScriptedAuthNotifier(
          container.read(apiClientProvider),
          storage,
          ref,
        ),
      ).notifier,
    );
    (auth as _ScriptedAuthNotifier).signIn();
    expect(auth.state.user, isNotNull);

    await auth.logout();

    expect(auth.state.user, isNull);
    expect(await storage.getAccessToken(), isNull);
  });
}
