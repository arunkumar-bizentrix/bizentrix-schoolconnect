import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/page_result.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/announcement_model.dart';

/// Announcement list state and admin/teacher-side circular management.

class AnnouncementsNotifier
    extends StateNotifier<AsyncValue<List<AnnouncementModel>>> {

  // ── pagination ───────────────────────────────────────────────────────────
  // The API pages at 20 rows. Without these the screen would show the first
  // page and look like the rest vanished.
  String? _nextPageUrl;
  bool _loadingMore = false;
  int _totalCount = 0;

  /// Rows on the server, including ones not loaded yet.
  int get totalCount => _totalCount;

  /// Whether another page is waiting.
  bool get hasMore => _nextPageUrl != null;

  /// Whether a `loadMore` call is in flight.
  bool get isLoadingMore => _loadingMore;

  /// Appends the next page to what is already on screen.
  Future<void> loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _loadingMore) return;

    _loadingMore = true;
    try {
      final response = await apiClient.dio.getUri(Uri.parse(url));
      final page = PageResult.parse(response.data, AnnouncementModel.fromJson);
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
    String? search,
  }) async {
    _currentAcademicYear = academicYear ?? _currentAcademicYear;
    _currentPriority = priority;
    _currentAudienceType = audienceType;

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

      final page = PageResult.parse(response.data, AnnouncementModel.fromJson);
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
  /// Matches the convention used by the classes, students and homework
  /// notifiers so screens can surface the server's validation message.
  Future<String?> createAnnouncement({
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
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }

  /// Returns null on success, or an error message describing the failure.
  Future<String?> deleteAnnouncement(int id) async {
    try {
      final response = await apiClient.dio.delete(ApiEndpoints.announcementDetail(id));
      if (response.statusCode == 204 || response.statusCode == 200) {
        await loadAnnouncements();
        return null;
      }
      return 'Unexpected server response (${response.statusCode}).';
    } catch (e) {
      return apiClient.handleError(e).message;
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
