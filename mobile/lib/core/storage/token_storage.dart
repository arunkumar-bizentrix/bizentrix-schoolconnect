import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});

class TokenStorage {
  final FlutterSecureStorage _storage;

  TokenStorage(this._storage);

  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    await _storage.write(key: AppConstants.tokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken);
    }
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConstants.tokenKey);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConstants.refreshTokenKey);
  }

  Future<void> saveUserRole(UserRole role) async {
    await _storage.write(key: AppConstants.userRoleKey, value: role.code);
  }

  Future<UserRole?> getUserRole() async {
    final code = await _storage.read(key: AppConstants.userRoleKey);
    return code != null ? UserRole.fromCode(code) : null;
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
