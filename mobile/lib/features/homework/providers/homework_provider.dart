import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/page_result.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/homework_model.dart';

/// Homework list state and teacher-side homework management.

class HomeworkNotifier extends StateNotifier<AsyncValue<List<HomeworkModel>>> {

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
      final page = PageResult.parse(response.data, HomeworkModel.fromJson);
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
    String? search,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentClassId = classId;
    _currentSubject = subject;

    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{
        'academic_year': _currentAcademicYear,
      };
      // Search runs on the server: filtering a single 20-row page on the
      // client would only ever search that page.
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
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

      final page = PageResult.parse(response.data, HomeworkModel.fromJson);
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
  Future<String?> createHomework({
    required int classId,
    int? studentId,
    required String subject,
    required String title,
    required String description,
    required DateTime dueDate,
    TimeOfDay? dueTime,
    Uint8List? attachmentBytes,
    String? attachmentFileName,
  }) async {
    try {
      final Map<String, dynamic> dataMap = {
        'classroom': classId,
        'subject': subject,
        'title': title,
        'description': description,
        'due_date': dueDate.toIso8601String().split('T').first,
        if (dueTime != null)
          'due_time':
              '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}',
      };
      if (studentId != null) {
        dataMap['student'] = studentId;
      }

      dynamic payload;
      if (attachmentBytes != null && attachmentBytes.isNotEmpty) {
        dataMap['attachment'] = MultipartFile.fromBytes(
          attachmentBytes,
          filename: attachmentFileName ?? 'homework-attachment',
        );
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
    TimeOfDay? dueTime,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (classId != null) data['classroom'] = classId;
      if (subject != null) data['subject'] = subject;
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (dueDate != null) data['due_date'] = dueDate.toIso8601String().split('T').first;
      if (dueTime != null) {
        data['due_time'] =
            '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}';
      }

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
