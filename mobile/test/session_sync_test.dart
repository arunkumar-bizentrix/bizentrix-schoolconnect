import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';
import 'package:school_connect/features/auth/providers/session_sync.dart';
import 'package:school_connect/features/notifications/providers/notifications_provider.dart';

/// Counts requests per path so a test can tell whether a provider reloaded.
class _CountingAdapter implements HttpClientAdapter {
  final Map<String, int> hits = {};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hits[options.path] = (hits[options.path] ?? 0) + 1;
    final body = options.path.contains('unread-count')
        ? '{"unread_count":0}'
        : '{"count":0,"next":null,"previous":null,"results":[]}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// Lets a test drive who is signed in without touching the network.
class _ScriptedAuthNotifier extends AuthNotifier {
  _ScriptedAuthNotifier(ApiClient client, TokenStorage storage)
      : super(apiClient: client, tokenStorage: storage);

  @override
  Future<bool> restoreSession() async => true;

  void signIn(String id, UserRole role) {
    state = AuthState(
      user: UserModel(
        id: id,
        email: '$id@example.test',
        fullName: 'User $id',
        role: role,
      ),
    );
  }

  void signOut() => state = const AuthState();
}

void main() {
  late _CountingAdapter adapter;
  late ProviderContainer container;
  late _ScriptedAuthNotifier auth;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    adapter = _CountingAdapter();
    final storage = TokenStorage(const FlutterSecureStorage());
    final client = ApiClient(tokenStorage: storage);
    client.dio.httpClientAdapter = adapter;

    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        authProvider.overrideWith((ref) {
          auth = _ScriptedAuthNotifier(client, storage);
          return auth;
        }),
      ],
    );
    addTearDown(container.dispose);

    // Mirrors the listener SchoolConnectApp installs at the app root.
    String? lastUserId;
    container.listen<AuthState>(authProvider, (previous, next) {
      if (lastUserId == next.user?.id) return;
      lastUserId = next.user?.id;
      for (final provider in userScopedProviders) {
        container.invalidate(provider);
      }
    }, fireImmediately: true);
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('switching account reloads notifications instead of showing the last user\'s', () async {
    auth.signIn('1', UserRole.parent);
    container.listen(notificationsProvider, (_, __) {});
    await settle();

    final afterFirstUser = adapter.hits['/notifications/'] ?? 0;
    expect(afterFirstUser, greaterThan(0),
        reason: 'the first account should have loaded its notifications');

    // A different parent signs in on the same device.
    auth.signIn('2', UserRole.parent);
    container.listen(notificationsProvider, (_, __) {});
    await settle();

    expect(
      adapter.hits['/notifications/'],
      greaterThan(afterFirstUser),
      reason: 'the second account must fetch its own notifications, not reuse '
          "the first account's list",
    );
  });

  test('signing out clears the previous account data', () async {
    auth.signIn('1', UserRole.parent);
    container.listen(notificationsProvider, (_, __) {});
    await settle();
    final afterSignIn = adapter.hits['/notifications/'] ?? 0;

    auth.signOut();
    await settle();

    // Reading again after sign-out must hit the network rather than replay
    // the signed-out user's cached list.
    container.listen(notificationsProvider, (_, __) {});
    await settle();

    expect(adapter.hits['/notifications/'], greaterThan(afterSignIn));
  });

  test('the same user staying signed in does not thrash the network', () async {
    auth.signIn('1', UserRole.parent);
    container.listen(notificationsProvider, (_, __) {});
    await settle();
    final afterFirstLoad = adapter.hits['/notifications/'] ?? 0;

    // Same id delivered again - nothing changed, so nothing should reload.
    auth.signIn('1', UserRole.parent);
    await settle();

    expect(adapter.hits['/notifications/'], afterFirstLoad);
  });
}
