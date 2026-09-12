import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/token_storage.dart';
import '../models/user_model.dart';

/// Authentication state: sign-in (password, WhatsApp OTP, email OTP),
/// session restore, profile updates and sign-out.

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({this.user, this.isLoading = false, this.errorMessage});

  bool get isAuthenticated => user != null;
  UserRole? get role => user?.role;

  AuthState copyWith({UserModel? user, bool? isLoading, String? errorMessage}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  AuthNotifier({required this.apiClient, required this.tokenStorage})
      : super(const AuthState()) {
    restoreSession();
  }

  /// Restore user session on app launch from secure storage and verify with backend
  Future<bool> restoreSession() async {
    final token = await tokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    // First, restore cached profile instantly if available
    final cachedJson = await tokenStorage.getUserProfileJson();
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final cachedUser = UserModel.fromJson(jsonDecode(cachedJson));
        state = AuthState(user: cachedUser);
      } catch (_) {}
    }

    // Verify session against Django backend /api/v1/auth/me/
    try {
      final response = await apiClient.dio.get(ApiEndpoints.userProfile);
      if (response.statusCode == 200 && response.data != null) {
        final user = UserModel.fromJson(response.data);
        await tokenStorage.saveUserRole(user.role);
        await tokenStorage.saveUserProfileJson(jsonEncode(response.data));
        state = AuthState(user: user);
        return true;
      }
    } catch (e) {
      final failure = apiClient.handleError(e);
      final isAuthError = failure is AuthFailure ||
          failure.message.contains('Session expired') ||
          failure.message.contains('unauthorized');
      if (isAuthError) {
        // Invalid/expired refresh token: drop the stale session entirely
        await tokenStorage.clearAll();
        state = const AuthState();
        return false;
      }
      // Network/server errors keep the cached profile so the app still
      // opens offline; the interceptor will refresh on the next request.
    }
    return state.isAuthenticated;
  }

  /// Real login against /api/v1/auth/token/ + /api/v1/auth/me/
  Future<bool> login(String username, String password) async {
    state = const AuthState(isLoading: true);
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.login,
        data: {'username': username, 'password': password},
      );

      final data = response.data;
      final accessToken = data['access']?.toString();
      final refreshToken = data['refresh']?.toString();

      if (accessToken == null || accessToken.isEmpty) {
        state = const AuthState(errorMessage: 'Authentication failed: No token received.');
        return false;
      }

      await tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      // Fetch user profile & role from /api/v1/auth/me/
      final profileRes = await apiClient.dio.get(
        ApiEndpoints.userProfile,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      final user = UserModel.fromJson(profileRes.data);
      await tokenStorage.saveUserRole(user.role);
      await tokenStorage.saveUserProfileJson(jsonEncode(profileRes.data));

      state = AuthState(user: user);
      return true;
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = AuthState(errorMessage: failure.message);
      return false;
    }
  }

  /// Request WhatsApp OTP for mobile login (/api/v1/auth/otp/send/)
  Future<Map<String, dynamic>> sendWhatsAppOtp(String phoneNumber) async {
    state = const AuthState(isLoading: true);
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.sendOtp,
        data: {'phone_number': phoneNumber},
      );
      state = const AuthState(isLoading: false);
      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': false, 'error': 'Unexpected response from server.'};
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = AuthState(errorMessage: failure.message);
      return {'success': false, 'error': failure.message};
    }
  }

  /// Verify WhatsApp OTP and sign in (/api/v1/auth/otp/verify/)
  Future<bool> verifyWhatsAppOtp(String phoneNumber, String otp) async {
    state = const AuthState(isLoading: true);
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone_number': phoneNumber,
          'otp': otp,
        },
      );

      final data = response.data;
      final accessToken = data['access']?.toString();
      final refreshToken = data['refresh']?.toString();

      if (accessToken == null || accessToken.isEmpty) {
        state = const AuthState(errorMessage: 'Authentication failed: No token received.');
        return false;
      }

      await tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      UserModel user;
      if (data['user'] != null && data['user'] is Map<String, dynamic>) {
        user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      } else {
        final profileRes = await apiClient.dio.get(
          ApiEndpoints.userProfile,
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        );
        user = UserModel.fromJson(profileRes.data);
      }

      await tokenStorage.saveUserRole(user.role);
      await tokenStorage.saveUserProfileJson(jsonEncode(user.toJson()));

      state = AuthState(user: user);
      return true;
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = AuthState(errorMessage: failure.message);
      return false;
    }
  }

  /// Request Email OTP for mobile login (/api/v1/auth/otp/email/send/)
  Future<Map<String, dynamic>> sendEmailOtp(String email) async {
    state = const AuthState(isLoading: true);
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.authOtpEmailSend,
        data: {'email': email.trim().toLowerCase()},
      );
      state = const AuthState(isLoading: false);
      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': false, 'error': 'Unexpected response from server.'};
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = AuthState(errorMessage: failure.message);
      return {'success': false, 'error': failure.message};
    }
  }

  /// Verify Email OTP and sign in (/api/v1/auth/otp/email/verify/)
  Future<bool> verifyEmailOtp(String email, String otp) async {
    state = const AuthState(isLoading: true);
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.authOtpEmailVerify,
        data: {
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
        },
      );

      final data = response.data;
      // Backend marks unregistered-but-verified emails as new users and
      // issues no tokens for them (registration flow is not built yet).
      if (data['is_new_user'] == true) {
        state = const AuthState(
          errorMessage:
              'This email is verified but no account exists yet. Account registration is coming soon — please sign in with your username and password.',
        );
        return false;
      }

      final accessToken = data['access']?.toString();
      final refreshToken = data['refresh']?.toString();

      if (accessToken == null || accessToken.isEmpty) {
        state = const AuthState(errorMessage: 'Authentication failed: No token received.');
        return false;
      }

      await tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      UserModel user;
      if (data['user'] != null && data['user'] is Map<String, dynamic>) {
        user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      } else {
        final profileRes = await apiClient.dio.get(
          ApiEndpoints.userProfile,
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        );
        user = UserModel.fromJson(profileRes.data);
      }

      await tokenStorage.saveUserRole(user.role);
      await tokenStorage.saveUserProfileJson(jsonEncode(user.toJson()));

      state = AuthState(user: user);
      return true;
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = AuthState(errorMessage: failure.message);
      return false;
    }
  }

  /// Update user profile picture via PATCH /api/v1/auth/me/
  Future<bool> updateProfilePicture({
    List<int>? bytes,
    String? filePath,
    required String filename,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      MultipartFile multipartFile;
      if (bytes != null) {
        multipartFile = MultipartFile.fromBytes(bytes, filename: filename);
      } else if (filePath != null) {
        multipartFile = await MultipartFile.fromFile(filePath, filename: filename);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: 'No file selected');
        return false;
      }

      final formData = FormData.fromMap({
        'profile_picture': multipartFile,
      });

      final response = await apiClient.dio.patch(
        ApiEndpoints.userProfile,
        data: formData,
      );

      if (response.statusCode == 200 && response.data != null) {
        final updatedUser = UserModel.fromJson(response.data);
        await tokenStorage.saveUserProfileJson(jsonEncode(response.data));
        state = state.copyWith(user: updatedUser, isLoading: false);
        return true;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: 'Failed to update profile picture.');
        return false;
      }
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = state.copyWith(isLoading: false, errorMessage: failure.message);
      return false;
    }
  }

  /// Update user profile details (name, phone, email) via PATCH /api/v1/auth/me/
  Future<bool> updateProfileDetails({
    required String fullName,
    String? phoneNumber,
    String? email,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final payload = <String, dynamic>{
        'full_name': fullName,
      };
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        payload['phone_number'] = phoneNumber;
      }
      if (email != null && email.isNotEmpty) {
        payload['email'] = email;
      }

      final response = await apiClient.dio.patch(
        ApiEndpoints.userProfile,
        data: payload,
      );

      if (response.statusCode == 200 && response.data != null) {
        final updatedUser = UserModel.fromJson(response.data);
        await tokenStorage.saveUserProfileJson(jsonEncode(response.data));
        state = state.copyWith(user: updatedUser, isLoading: false);
        return true;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: 'Failed to update profile details.');
        return false;
      }
    } catch (e) {
      final failure = apiClient.handleError(e);
      state = state.copyWith(isLoading: false, errorMessage: failure.message);
      return false;
    }
  }

  Future<void> logout() async {
    await tokenStorage.clearAll();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return AuthNotifier(apiClient: apiClient, tokenStorage: tokenStorage);
});
