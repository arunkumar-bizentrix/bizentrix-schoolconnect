import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/attendance_model.dart';

/// Which class and date the register screen is showing.
class AttendanceQuery {
  const AttendanceQuery({required this.classId, required this.date});

  final int classId;
  final DateTime date;

  String get isoDate =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is AttendanceQuery && other.classId == classId && other.isoDate == isoDate;

  @override
  int get hashCode => Object.hash(classId, isoDate);
}

/// The register for one class on one day. Students with no mark yet come back
/// with a null status so the screen can default them to Present.
final attendanceSheetProvider =
    FutureProvider.family<AttendanceSheet, AttendanceQuery>((ref, query) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.attendanceSheet,
    queryParameters: {'class_id': query.classId, 'date': query.isoDate},
  );
  return AttendanceSheet.fromJson(Map<String, dynamic>.from(response.data as Map));
});

/// One child's attendance percentage and recent days.
final attendanceSummaryProvider =
    FutureProvider.family<AttendanceSummary, int>((ref, studentId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.attendanceSummary,
    queryParameters: {'student_id': studentId},
  );
  return AttendanceSummary.fromJson(Map<String, dynamic>.from(response.data as Map));
});

/// Submits a whole class in one request.
class AttendanceMarker {
  AttendanceMarker(this.apiClient);

  final ApiClient apiClient;

  /// Returns null on success, or the server's message on failure.
  Future<String?> markClass({
    required int classId,
    required String isoDate,
    required List<AttendanceEntry> entries,
  }) async {
    final marked = entries.where((entry) => entry.status != null).toList();
    if (marked.isEmpty) return 'Mark at least one student.';

    try {
      await apiClient.dio.post(
        ApiEndpoints.attendanceMark,
        data: {
          'classroom': classId,
          'date': isoDate,
          'entries': [
            for (final entry in marked)
              {
                'student': entry.studentId,
                'status': entry.status!.code,
                if (entry.note.isNotEmpty) 'note': entry.note,
              },
          ],
        },
      );
      return null;
    } catch (e) {
      return apiClient.handleError(e).message;
    }
  }
}

final attendanceMarkerProvider = Provider<AttendanceMarker>((ref) {
  return AttendanceMarker(ref.watch(apiClientProvider));
});
