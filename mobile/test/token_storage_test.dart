import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/storage/token_storage.dart';

/// Unit tests for secure token/session persistence, backed by the
/// flutter_secure_storage in-memory mock. No network, no real keystore.
void main() {
  group('TokenStorage Persistence Tests', () {
    test('Saves, retrieves, and clears tokens and profile', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = TokenStorage(const FlutterSecureStorage());

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.hasValidSession(), isFalse);

      await storage.saveTokens(
        accessToken: 'mock_access_jwt',
        refreshToken: 'mock_refresh_jwt',
      );

      expect(await storage.getAccessToken(), 'mock_access_jwt');
      expect(await storage.getRefreshToken(), 'mock_refresh_jwt');
      expect(await storage.hasValidSession(), isTrue);

      final profileJson = jsonEncode({'id': '1', 'name': 'Admin User'});
      await storage.saveUserProfileJson(profileJson);
      expect(await storage.getUserProfileJson(), profileJson);

      await storage.clearAll();
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getUserProfileJson(), isNull);
      expect(await storage.hasValidSession(), isFalse);
    });
  });

}
