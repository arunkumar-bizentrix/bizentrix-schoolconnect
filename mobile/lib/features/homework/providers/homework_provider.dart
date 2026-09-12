import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/homework_model.dart';

/// Homework list state and teacher-side homework management.

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
    required int classId,
    int? studentId,
    required String subject,
    required String title,
    required String description,
    required DateTime dueDate,
    String? attachmentFilePath,
  }) async {
    try {
      final Map<String, dynamic> dataMap = {
        'classroom': classId,
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
    int? classId,
    String? subject,
    String? title,
    String? description,
    DateTime? dueDate,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (classId != null) data['classroom'] = classId;
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
