import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/page_result.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/student_model.dart';

/// Student list state and admin-side student management.

class StudentsNotifier extends StateNotifier<AsyncValue<List<StudentModel>>> {

  // ── pagination ───────────────────────────────────────────────────────────
  // The API pages at 20 rows. Without these the screen would show the first
  // page of a 1000-row roll and look like the rest vanished.
  String? _nextPageUrl;
  bool _loadingMore = false;
  int _totalCount = 0;

  /// Rows on the server, including ones not loaded yet.
  int get totalCount => _totalCount;

  /// Whether another page is waiting.
  bool get hasMore => _nextPageUrl != null;

  /// Whether a `loadMore` call is in flight.
  bool get isLoadingMore => _loadingMore;

  /// Appends the next page to what is already on screen. Safe to call from a
  /// scroll listener: it no-ops while one is in flight or when the list is
  /// already complete.
  Future<void> loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _loadingMore) return;

    _loadingMore = true;
    try {
      final response = await apiClient.dio.getUri(Uri.parse(url));
      final page = PageResult.parse(response.data, StudentModel.fromJson);
      _nextPageUrl = page.nextUrl;
      _totalCount = page.totalCount;
      if (!mounted) return;
      state = AsyncValue.data([...?state.value, ...page.items]);
    } catch (_) {
      // Keep what is already displayed; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }
  final ApiClient apiClient;
  String? _currentAcademicYear;
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
    if (academicYear != null) _currentAcademicYear = academicYear;
    _currentClassId = classId;
    _currentSearch = search;

    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{};
      if (_currentAcademicYear != null) {
        queryParams['academic_year'] = _currentAcademicYear;
      }
      if (_currentClassId != null) {
        queryParams['class_id'] = _currentClassId;
      }
      if (_currentSearch != null && _currentSearch!.trim().isNotEmpty) {
        queryParams['name'] = _currentSearch!.trim();
      }

      final response = await apiClient.dio.get(
        ApiEndpoints.students,
        queryParameters: queryParams,
      );

      final page = PageResult.parse(response.data, StudentModel.fromJson);
      _nextPageUrl = page.nextUrl;
      _totalCount = page.totalCount;
      if (!mounted) return;
      state = AsyncValue.data(page.items);
    } catch (e, st) {
      if (!mounted) return;
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

  /// Links a parent account to a student. Admin only on the backend.
  /// Returns null on success, or the server's message on failure.
  Future<String?> linkParent(int studentId, int parentId) async {
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.studentLinkParent(studentId),
        data: {'parent_id': parentId},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await loadStudents();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Removes a parent link. Returns null on success.
  Future<String?> unlinkParent(int studentId, int parentId) async {
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.studentUnlinkParent(studentId),
        data: {'parent_id': parentId},
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

  /// Uploads a roll CSV. With [dryRun] the server validates and reports but
  /// keeps nothing, so the admin can check the file before committing.
  ///
  /// Returns the server's summary, or throws the message to show the user.
  Future<Map<String, dynamic>> importRoll({
    required List<int> bytes,
    required String filename,
    required String academicYear,
    bool dryRun = false,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'academic_year': academicYear,
        'dry_run': dryRun.toString(),
      });

      final response = await apiClient.dio.post(
        ApiEndpoints.studentImport,
        data: formData,
      );
      if (!dryRun) await loadStudents();
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw apiClient.handleError(e).message;
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
