import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/school/models/class_model.dart';
import '../../features/school/models/student_model.dart';
import '../../features/homework/models/homework_model.dart';
import '../../features/announcements/models/announcement_model.dart';
import '../../features/notifications/models/notification_model.dart';
import '../errors/failures.dart';
import '../storage/token_storage.dart';

// ═══════════════════════════════════════════════════════
// AUTH STATE & NOTIFIER (REAL SIMPLEJWT)
// ═══════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════
// CLASSES (REAL DJANGO REST API)
// ═══════════════════════════════════════════════════════

class ClassesNotifier extends StateNotifier<AsyncValue<List<ClassModel>>> {
  final ApiClient apiClient;
  String _currentAcademicYear = AppConstants.currentAcademicYear;
  String? _currentSection;

  ClassesNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadClasses();
  }

  Future<void> loadClasses({
    String? academicYear,
    String? section,
    String? name,
    bool? assignedToMe,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentSection = section;

    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{
        'academic_year': _currentAcademicYear,
      };
      if (_currentSection != null && _currentSection!.isNotEmpty) {
        queryParams['section'] = _currentSection;
      }
      if (name != null && name.isNotEmpty) {
        queryParams['name'] = name;
      }
      if (assignedToMe == true) {
        queryParams['assigned_to_me'] = 'true';
      }

      final response = await apiClient.dio.get(
        ApiEndpoints.classes,
        queryParameters: queryParams,
      );

      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final classes = results.map((item) => ClassModel.fromJson(item)).toList();
      state = AsyncValue.data(classes);
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> createClass({
    required String name,
    required String section,
    String academicYear = AppConstants.currentAcademicYear,
  }) async {
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.classes,
        data: {
          'name': name,
          'section': section,
          'academic_year': academicYear,
        },
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        await loadClasses();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> updateClass(
    int id, {
    required String name,
    required String section,
    String academicYear = AppConstants.currentAcademicYear,
  }) async {
    try {
      final response = await apiClient.dio.patch(
        ApiEndpoints.classDetail(id),
        data: {
          'name': name,
          'section': section,
          'academic_year': academicYear,
        },
      );
      if (response.statusCode == 200) {
        await loadClasses();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> deleteClass(int id) async {
    try {
      final response = await apiClient.dio.delete(ApiEndpoints.classDetail(id));
      if (response.statusCode == 204 || response.statusCode == 200) {
        await loadClasses();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  void refresh() {
    loadClasses();
  }
}

final classesProvider =
    StateNotifierProvider<ClassesNotifier, AsyncValue<List<ClassModel>>>((ref) {
  return ClassesNotifier(ref.watch(apiClientProvider));
});

// ═══════════════════════════════════════════════════════
// STUDENTS (REAL DJANGO REST API)
// ═══════════════════════════════════════════════════════

class StudentsNotifier extends StateNotifier<AsyncValue<List<StudentModel>>> {
  final ApiClient apiClient;
  String _currentAcademicYear = AppConstants.currentAcademicYear;
  int? _currentClassId;
  String? _currentSearch;

  StudentsNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadStudents();
  }

  Future<void> loadStudents({
    String? academicYear,
    int? classId,
    String? search,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentClassId = classId;
    _currentSearch = search;

    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{
        'academic_year': _currentAcademicYear,
      };
      if (_currentClassId != null) {
        queryParams['class_id'] = _currentClassId;
      }
      if (_currentSearch != null && _currentSearch!.trim().isNotEmpty) {
        queryParams['search'] = _currentSearch!.trim();
      }

      final response = await apiClient.dio.get(
        ApiEndpoints.students,
        queryParameters: queryParams,
      );

      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final students = results.map((item) => StudentModel.fromJson(item)).toList();
      state = AsyncValue.data(students);
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> createStudent({
    required String firstName,
    required String lastName,
    required String admissionNumber,
    required int classEnrolled,
  }) async {
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.students,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'admission_number': admissionNumber,
          'class_enrolled': classEnrolled,
        },
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        await loadStudents();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> updateStudent(
    int id, {
    String? firstName,
    String? lastName,
    String? admissionNumber,
    int? classEnrolled,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (admissionNumber != null) data['admission_number'] = admissionNumber;
      if (classEnrolled != null) data['class_enrolled'] = classEnrolled;

      final response = await apiClient.dio.patch(
        ApiEndpoints.studentDetail(id),
        data: data,
      );
      if (response.statusCode == 200) {
        await loadStudents();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> deleteStudent(int id) async {
    try {
      final response = await apiClient.dio.delete(ApiEndpoints.studentDetail(id));
      if (response.statusCode == 204 || response.statusCode == 200) {
        await loadStudents();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  void refresh() {
    loadStudents();
  }
}

final studentsProvider =
    StateNotifierProvider<StudentsNotifier, AsyncValue<List<StudentModel>>>((ref) {
  return StudentsNotifier(ref.watch(apiClientProvider));
});

// ═══════════════════════════════════════════════════════
// HOMEWORK (REAL DJANGO REST API)
// ═══════════════════════════════════════════════════════

class HomeworkNotifier extends StateNotifier<AsyncValue<List<HomeworkModel>>> {
  final ApiClient apiClient;
  String _currentAcademicYear = AppConstants.currentAcademicYear;
  int? _currentClassId;
  String? _currentSubject;

  HomeworkNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadHomework();
  }

  Future<void> loadHomework({
    String? academicYear,
    int? classId,
    String? subject,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentClassId = classId;
    _currentSubject = subject;

    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{
        'academic_year': _currentAcademicYear,
      };
      if (_currentClassId != null) {
        queryParams['class_id'] = _currentClassId;
      }
      if (_currentSubject != null && _currentSubject!.isNotEmpty) {
        queryParams['subject'] = _currentSubject;
      }

      final response = await apiClient.dio.get(
        ApiEndpoints.homeworkList,
        queryParameters: queryParams,
      );

      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final homework = results.map((item) => HomeworkModel.fromJson(item)).toList();
      state = AsyncValue.data(homework);
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> createHomework({
    required int classroomId,
    int? studentId,
    required String subject,
    required String title,
    required String description,
    required DateTime dueDate,
    String? attachmentFilePath,
  }) async {
    try {
      final Map<String, dynamic> dataMap = {
        'classroom': classroomId,
        'subject': subject,
        'title': title,
        'description': description,
        'due_date': dueDate.toIso8601String().split('T').first,
      };
      if (studentId != null) {
        dataMap['student'] = studentId;
      }

      dynamic payload;
      if (attachmentFilePath != null && attachmentFilePath.isNotEmpty) {
        dataMap['attachment'] = await MultipartFile.fromFile(attachmentFilePath);
        payload = FormData.fromMap(dataMap);
      } else {
        payload = dataMap;
      }

      final response = await apiClient.dio.post(
        ApiEndpoints.homeworkList,
        data: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        await loadHomework();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> updateHomework(
    int id, {
    int? classroomId,
    String? subject,
    String? title,
    String? description,
    DateTime? dueDate,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (classroomId != null) data['classroom'] = classroomId;
      if (subject != null) data['subject'] = subject;
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (dueDate != null) data['due_date'] = dueDate.toIso8601String().split('T').first;

      final response = await apiClient.dio.patch(
        ApiEndpoints.homeworkDetail(id),
        data: data,
      );
      if (response.statusCode == 200) {
        await loadHomework();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> deleteHomework(int id) async {
    try {
      final response = await apiClient.dio.delete(ApiEndpoints.homeworkDetail(id));
      if (response.statusCode == 204 || response.statusCode == 200) {
        await loadHomework();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  void refresh() {
    loadHomework();
  }
}

final homeworkProvider =
    StateNotifierProvider<HomeworkNotifier, AsyncValue<List<HomeworkModel>>>((ref) {
  return HomeworkNotifier(ref.watch(apiClientProvider));
});

// ═══════════════════════════════════════════════════════
// ANNOUNCEMENTS (REAL DJANGO REST API)
// ═══════════════════════════════════════════════════════

class AnnouncementsNotifier
    extends StateNotifier<AsyncValue<List<AnnouncementModel>>> {
  final ApiClient apiClient;
  String _currentAcademicYear = AppConstants.currentAcademicYear;
  String? _currentPriority;
  String? _currentAudienceType;

  AnnouncementsNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadAnnouncements();
  }

  Future<void> loadAnnouncements({
    String? academicYear,
    String? priority,
    String? audienceType,
    int? classId,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentPriority = priority;
    _currentAudienceType = audienceType;

    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{
        'academic_year': _currentAcademicYear,
      };
      if (_currentPriority != null && _currentPriority!.isNotEmpty) {
        queryParams['priority'] = _currentPriority;
      }
      if (_currentAudienceType != null && _currentAudienceType!.isNotEmpty) {
        queryParams['audience_type'] = _currentAudienceType;
      }
      if (classId != null) {
        queryParams['class_id'] = classId;
      }

      final response = await apiClient.dio.get(
        ApiEndpoints.announcements,
        queryParameters: queryParams,
      );

      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final notices = results.map((item) => AnnouncementModel.fromJson(item)).toList();
      state = AsyncValue.data(notices);
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  Future<bool> createAnnouncement({
    required String title,
    required String content,
    String priority = 'NORMAL',
    String audienceType = 'SCHOOL',
    int? targetClassId,
    String? attachmentFilePath,
  }) async {
    try {
      dynamic payload;
      final mapData = <String, dynamic>{
        'title': title,
        'content': content,
        'priority': priority.toUpperCase(),
        'audience_type': audienceType.toUpperCase(),
      };
      if (targetClassId != null && audienceType.toUpperCase() == 'CLASS') {
        mapData['target_class'] = targetClassId;
      }

      if (attachmentFilePath != null && attachmentFilePath.isNotEmpty) {
        mapData['attachment'] = await MultipartFile.fromFile(attachmentFilePath);
        payload = FormData.fromMap(mapData);
      } else {
        payload = mapData;
      }

      final response = await apiClient.dio.post(
        ApiEndpoints.announcements,
        data: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        await loadAnnouncements();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteAnnouncement(int id) async {
    try {
      final response = await apiClient.dio.delete(ApiEndpoints.announcementDetail(id));
      if (response.statusCode == 204 || response.statusCode == 200) {
        await loadAnnouncements();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void refresh() {
    loadAnnouncements();
  }
}

final announcementsProvider = StateNotifierProvider<AnnouncementsNotifier,
    AsyncValue<List<AnnouncementModel>>>((ref) {
  return AnnouncementsNotifier(ref.watch(apiClientProvider));
});

// ═══════════════════════════════════════════════════════
// PARENT CHILDREN (REAL DJANGO REST API)
// ═══════════════════════════════════════════════════════

class ParentChildrenNotifier extends StateNotifier<AsyncValue<List<StudentModel>>> {
  final ApiClient apiClient;

  ParentChildrenNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadChildren();
  }

  Future<void> loadChildren() async {
    state = const AsyncValue.loading();
    try {
      final response = await apiClient.dio.get(ApiEndpoints.parentChildren);
      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final children = results.map((item) => StudentModel.fromJson(item)).toList();
      state = AsyncValue.data(children);
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  void refresh() {
    loadChildren();
  }
}

final parentChildrenProvider = StateNotifierProvider<ParentChildrenNotifier,
    AsyncValue<List<StudentModel>>>((ref) {
  return ParentChildrenNotifier(ref.watch(apiClientProvider));
});

final selectedParentChildProvider = StateProvider<StudentModel?>((ref) => null);

// ═══════════════════════════════════════════════════════
// NOTIFICATIONS (REAL DJANGO REST API)
// ═══════════════════════════════════════════════════════

class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final ApiClient apiClient;
  final Ref ref;

  NotificationsNotifier(this.apiClient, this.ref)
      : super(const AsyncValue.loading()) {
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    state = const AsyncValue.loading();
    try {
      final response = await apiClient.dio.get(ApiEndpoints.notifications);
      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final notifications =
          results.map((item) => NotificationModel.fromJson(item)).toList();
      state = AsyncValue.data(notifications);
      await ref.read(unreadNotificationsCountProvider.notifier).fetchCount();
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  Future<bool> markAsRead(int notificationId) async {
    try {
      final response =
          await apiClient.dio.post(ApiEndpoints.notificationRead(notificationId));
      if (response.statusCode == 200) {
        state.whenData((list) {
          state = AsyncValue.data(
            list.map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n).toList(),
          );
        });
        ref.read(unreadNotificationsCountProvider.notifier).decrement();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      final response =
          await apiClient.dio.post(ApiEndpoints.notificationsMarkAllRead);
      if (response.statusCode == 200) {
        state.whenData((list) {
          state = AsyncValue.data(
            list.map((n) => n.copyWith(isRead: true)).toList(),
          );
        });
        ref.read(unreadNotificationsCountProvider.notifier).reset();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void refresh() {
    loadNotifications();
  }
}

final notificationsProvider = StateNotifierProvider<NotificationsNotifier,
    AsyncValue<List<NotificationModel>>>((ref) {
  return NotificationsNotifier(ref.watch(apiClientProvider), ref);
});

class UnreadNotificationsCountNotifier extends StateNotifier<int> {
  final ApiClient apiClient;

  UnreadNotificationsCountNotifier(this.apiClient) : super(0) {
    fetchCount();
  }

  Future<void> fetchCount() async {
    try {
      final response =
          await apiClient.dio.get(ApiEndpoints.notificationsUnreadCount);
      if (response.statusCode == 200 && response.data != null) {
        final count = response.data['unread_count'] as int? ?? 0;
        state = count;
      }
    } catch (_) {}
  }

  void decrement() {
    if (state > 0) state = state - 1;
  }

  void reset() {
    state = 0;
  }
}

final unreadNotificationsCountProvider =
    StateNotifierProvider<UnreadNotificationsCountNotifier, int>((ref) {
  return UnreadNotificationsCountNotifier(ref.watch(apiClientProvider));
});

