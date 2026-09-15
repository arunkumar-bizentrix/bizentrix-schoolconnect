import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/page_result.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/class_model.dart';

/// Class list state and admin-side class management.

class ClassesNotifier extends StateNotifier<AsyncValue<List<ClassModel>>> {

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
      final page = PageResult.parse(response.data, ClassModel.fromJson);
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
  String? _currentSection;

  ClassesNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadClasses();
  }

  Future<void> loadClasses({
    String? academicYear,
    String? section,
    String? name,
    bool? assignedToMe,
    String? search,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentSection = section;

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

      final page = PageResult.parse(response.data, ClassModel.fromJson);
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
  Future<String?> createClass({
    required String name,
    required String section,
    String academicYear = AppConstants.currentAcademicYear,
    List<int>? teacherIds,
    int? classTeacherId,
  }) async {
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.classes,
        data: {
          'name': name,
          'section': section,
          'academic_year': academicYear,
          if (teacherIds != null) 'teachers': teacherIds,
          // Sent whenever teachers are, so clearing it is possible too.
          if (teacherIds != null) 'class_teacher': classTeacherId,
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
    List<int>? teacherIds,
    int? classTeacherId,
  }) async {
    try {
      final response = await apiClient.dio.patch(
        ApiEndpoints.classDetail(id),
        data: {
          'name': name,
          'section': section,
          'academic_year': academicYear,
          if (teacherIds != null) 'teachers': teacherIds,
          // Sent whenever teachers are, so clearing it is possible too.
          if (teacherIds != null) 'class_teacher': classTeacherId,
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
