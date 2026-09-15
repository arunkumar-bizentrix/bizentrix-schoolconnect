import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/subject_model.dart';
import 'timetable_provider.dart';

/// The school's subject list. Admin writes; everyone reads.
final subjectsProvider = FutureProvider<List<SubjectModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.subjects);
  final data = response.data;
  final rows = data is List ? data : (data['results'] ?? const []);
  return (rows as List)
      .whereType<Map<String, dynamic>>()
      .map(SubjectModel.fromJson)
      .toList();
});

/// Admin-only writes against the timetable and subject list.
///
/// Every method returns null on success or the server's message, so the
/// screen can surface a real conflict ("Priya already teaches 6-B in period 1")
/// rather than a generic failure.
class TimetableEditor {
  TimetableEditor(this.ref);

  final Ref ref;

  ApiClient get _apiClient => ref.read(apiClientProvider);

  void _refresh(int classId) {
    ref.invalidate(classTimetableProvider(classId));
    ref.invalidate(myTimetableProvider);
  }

  Future<String?> addPeriod({
    required int classId,
    required int weekday,
    required int period,
    required int subjectId,
    int? teacherId,
    String? startTime,
    String? endTime,
    String room = '',
  }) async {
    try {
      await _apiClient.dio.post(ApiEndpoints.timetable, data: {
        'classroom': classId,
        'weekday': weekday,
        'period': period,
        'subject': subjectId,
        if (teacherId != null) 'teacher': teacherId,
        if (startTime != null && startTime.isNotEmpty) 'start_time': startTime,
        if (endTime != null && endTime.isNotEmpty) 'end_time': endTime,
        if (room.isNotEmpty) 'room': room,
      });
      _refresh(classId);
      return null;
    } catch (e) {
      return _apiClient.handleError(e).message;
    }
  }

  Future<String?> updatePeriod({
    required int slotId,
    required int classId,
    required int subjectId,
    int? teacherId,
    String? startTime,
    String? endTime,
    String room = '',
  }) async {
    try {
      await _apiClient.dio.patch('${ApiEndpoints.timetable}$slotId/', data: {
        'subject': subjectId,
        'teacher': teacherId,
        'start_time': (startTime?.isEmpty ?? true) ? null : startTime,
        'end_time': (endTime?.isEmpty ?? true) ? null : endTime,
        'room': room,
      });
      _refresh(classId);
      return null;
    } catch (e) {
      return _apiClient.handleError(e).message;
    }
  }

  Future<String?> deletePeriod({required int slotId, required int classId}) async {
    try {
      await _apiClient.dio.delete('${ApiEndpoints.timetable}$slotId/');
      _refresh(classId);
      return null;
    } catch (e) {
      return _apiClient.handleError(e).message;
    }
  }

  /// Adds a subject the school has not used before, straight from the period
  /// dialog - an admin should not have to leave the screen to add "Tamil".
  Future<String?> addSubject(String name) async {
    try {
      await _apiClient.dio.post(ApiEndpoints.subjects, data: {'name': name.trim()});
      ref.invalidate(subjectsProvider);
      return null;
    } catch (e) {
      return _apiClient.handleError(e).message;
    }
  }
}

final timetableEditorProvider = Provider<TimetableEditor>(TimetableEditor.new);
