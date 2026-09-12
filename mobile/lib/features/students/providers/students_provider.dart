import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/student_model.dart';

/// Student list state and admin-side student management.

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
