import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';

/// Firebase Cloud Messaging, wired so the app works with or without it.
///
/// Push is what makes a parent's phone buzz when homework is set or their
/// child is marked absent; without it a notification is only seen if someone
/// happens to open the app.
///
/// Every entry point here is defensive on purpose. Until the school adds
/// `google-services.json`, `Firebase.initializeApp()` throws - that must leave
/// the app completely unaffected, not crash it at startup.
class PushService {
  PushService(this._apiClient);

  final ApiClient _apiClient;

  static bool _initialised = false;
  static bool _available = false;
  String? _registeredToken;

  /// Whether Firebase actually came up on this device.
  bool get isAvailable => _available;

  /// Lets a test exercise the paths that only run on a push-capable device.
  @visibleForTesting
  static set debugAvailable(bool value) {
    _initialised = true;
    _available = value;
  }

  /// Brings Firebase up once per app launch. Safe to call repeatedly.
  ///
  /// Returns false when push is not configured - which is a normal state, not
  /// an error.
  static Future<bool> initialise() async {
    if (_initialised) return _available;
    _initialised = true;

    // Web push needs its own Firebase config and a service worker; this build
    // targets Android, so web deliberately runs without push.
    if (kIsWeb) {
      _available = false;
      return false;
    }

    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (error) {
      // No google-services.json yet, or the file is malformed. The app keeps
      // working; notifications simply stay in-app.
      debugPrint('Push unavailable: ${error.runtimeType}');
      _available = false;
    }
    return _available;
  }

  /// Asks for permission, collects the device token and tells the backend.
  ///
  /// Called after sign-in, so the token lands against the right account.
  Future<void> registerDevice() async {
    if (!_available) return;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push permission denied by the user.');
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _sendToken(token);

      // Firebase rotates tokens; keep the backend pointing at the live one.
      messaging.onTokenRefresh.listen(_sendToken);
    } catch (error) {
      debugPrint('Could not register for push: ${error.runtimeType}');
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      await _apiClient.dio.post(
        ApiEndpoints.registerDevice,
        data: {
          'token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
        },
      );
      _registeredToken = token;
    } catch (error) {
      // A failed registration is not worth interrupting sign-in for; the next
      // launch tries again.
      debugPrint('Device registration failed: ${error.runtimeType}');
    }
  }

  /// Removes this device from the signed-out account.
  ///
  /// Without this the next person to use the phone would receive the previous
  /// user's notifications.
  Future<void> unregisterDevice() async {
    final token = _registeredToken;
    if (!_available || token == null) return;

    try {
      await _apiClient.dio.delete(
        ApiEndpoints.registerDevice,
        data: {'token': token},
      );
    } catch (error) {
      debugPrint('Device de-registration failed: ${error.runtimeType}');
    } finally {
      _registeredToken = null;
    }
  }

  /// Streams notifications that arrive while the app is open, so the in-app
  /// list and the unread badge can refresh without waiting for a reload.
  Stream<RemoteMessage> get onForegroundMessage {
    if (!_available) return const Stream<RemoteMessage>.empty();
    return FirebaseMessaging.onMessage;
  }

  /// Fires when the user taps a notification and the app opens from it.
  Stream<RemoteMessage> get onNotificationTapped {
    if (!_available) return const Stream<RemoteMessage>.empty();
    return FirebaseMessaging.onMessageOpenedApp;
  }
}


/// App-wide push service, sharing the authenticated Dio client.
final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(apiClientProvider));
});
