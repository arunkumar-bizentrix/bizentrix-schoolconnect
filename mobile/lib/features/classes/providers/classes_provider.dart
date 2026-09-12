import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/class_model.dart';

/// Class list state and admin-side class management.

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
