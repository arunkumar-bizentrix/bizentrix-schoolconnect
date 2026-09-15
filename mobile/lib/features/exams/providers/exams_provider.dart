import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/fetch_all_pages.dart';
import '../models/exam_models.dart';

List<Map<String, dynamic>> _rows(dynamic data) {
  final list = data is List ? data : ((data as Map)['results'] as List? ?? const []);
  return list.whereType<Map<String, dynamic>>().toList();
}

/// Exams the signed-in user can see: all for an admin, their classes' for a
/// teacher, published ones for a parent.
final examsProvider = FutureProvider.autoDispose<List<ExamModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return fetchAllPages(
    apiClient.dio,
    ApiEndpoints.exams,
    fromJson: ExamModel.fromJson,
    idOf: (exam) => exam.id,
  );
});

final examDetailProvider = FutureProvider.autoDispose.family<ExamModel, int>((ref, examId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.examDetail(examId));
  return ExamModel.fromJson(Map<String, dynamic>.from(response.data as Map));
});

final examPapersProvider =
    FutureProvider.autoDispose.family<List<ExamPaperModel>, int>((ref, examId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.examPapers(examId));
  return _rows(response.data).map(ExamPaperModel.fromJson).toList();
});

final markSheetProvider = FutureProvider.autoDispose.family<MarkSheet, int>((ref, paperId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.examPaperMarks(paperId));
  return MarkSheet.fromJson(Map<String, dynamic>.from(response.data as Map));
});

final classResultsProvider =
    FutureProvider.autoDispose.family<ClassResults, ({int examId, int classId})>((ref, key) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.examResults(key.examId),
    queryParameters: {'class_id': key.classId},
  );
  return ClassResults.fromJson(Map<String, dynamic>.from(response.data as Map));
});

final reportCardProvider = FutureProvider.autoDispose.family<ReportCard, int>((ref, studentId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.reportCard,
    queryParameters: {'student_id': studentId},
  );
  return ReportCard.fromJson(Map<String, dynamic>.from(response.data as Map));
});

/// The school's grading scale. Grades themselves are always computed by the
/// backend; this is only for showing and editing the scale.
final gradeScaleProvider = FutureProvider.autoDispose<GradeScale>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.gradeScale);
  return GradeScale.fromJson(Map<String, dynamic>.from(response.data as Map));
});

/// Writes against exams. Every method returns null on success or the
/// server's message, so a screen can show the real reason ("7 marks are still
/// not entered...") instead of a generic failure.
class ExamActions {
  ExamActions(this.ref);

  final Ref ref;

  ApiClient get _api => ref.read(apiClientProvider);

  Future<(int?, String?)> createExam({
    required String name,
    required String academicYear,
    DateTime? startDate,
    DateTime? endDate,
    required List<int> classroomIds,
    required List<int> subjectIds,
    required int maxMarks,
    required int passMarks,
  }) async {
    try {
      final response = await _api.dio.post(ApiEndpoints.exams, data: {
        'name': name.trim(),
        'academic_year': academicYear,
        if (startDate != null) 'start_date': _day(startDate),
        if (endDate != null) 'end_date': _day(endDate),
        'classroom_ids': classroomIds,
        'subject_ids': subjectIds,
        'max_marks': maxMarks,
        'pass_marks': passMarks,
      });
      ref.invalidate(examsProvider);
      return ((response.data as Map)['id'] as int?, null);
    } catch (e) {
      return (null, _api.handleError(e).message);
    }
  }

  Future<String?> deleteExam(int examId) => _run(() async {
        await _api.dio.delete(ApiEndpoints.examDetail(examId));
        ref.invalidate(examsProvider);
      });

  Future<String?> updatePaper(int paperId, int examId, {int? maxMarks, int? passMarks}) => _run(() async {
        await _api.dio.patch(ApiEndpoints.examPaperDetail(paperId), data: {
          if (maxMarks != null) 'max_marks': maxMarks,
          if (passMarks != null) 'pass_marks': passMarks,
        });
        ref.invalidate(examPapersProvider(examId));
      });

  Future<String?> saveMarks(int paperId, int examId, List<MarkEntry> entries) => _run(() async {
        await _api.dio.post(ApiEndpoints.examPaperMarks(paperId), data: {
          'entries': [
            for (final entry in entries)
              {
                'student': entry.studentId,
                'is_absent': entry.isAbsent,
                'marks_obtained': entry.isAbsent ? null : entry.marks,
              },
          ],
        });
        ref.invalidate(markSheetProvider(paperId));
        ref.invalidate(examPapersProvider(examId));
      });

  Future<int> missingMarks(int examId) async {
    try {
      final response = await _api.dio.get(ApiEndpoints.examProgress(examId));
      return ((response.data as Map)['missing_total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return -1;
    }
  }

  /// Returns (parents notified, error).
  Future<(int, String?)> publish(int examId, {bool allowIncomplete = false}) async {
    try {
      final response = await _api.dio.post(
        ApiEndpoints.examPublish(examId),
        data: {'allow_incomplete': allowIncomplete},
      );
      _refreshExam(examId);
      return (((response.data as Map)['parents_notified'] as num?)?.toInt() ?? 0, null);
    } catch (e) {
      return (0, _api.handleError(e).message);
    }
  }

  Future<String?> unpublish(int examId) => _run(() async {
        await _api.dio.post(ApiEndpoints.examUnpublish(examId));
        _refreshExam(examId);
      });

  Future<String?> saveGradeScale(List<GradeBand> bands) => _run(() async {
        await _api.dio.put(ApiEndpoints.gradeScale, data: {
          'bands': [for (final band in bands) band.toJson()],
        });
        ref.invalidate(gradeScaleProvider);
        ref.invalidate(reportCardProvider);
        ref.invalidate(classResultsProvider);
      });

  void _refreshExam(int examId) {
    ref.invalidate(examsProvider);
    ref.invalidate(examDetailProvider(examId));
    ref.invalidate(examPapersProvider(examId));
  }

  Future<String?> _run(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (e) {
      return _api.handleError(e).message;
    }
  }

  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

final examActionsProvider = Provider<ExamActions>((ref) => ExamActions(ref));
