import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/fetch_all_pages.dart';
import '../models/class_model.dart';

/// Every class the signed-in user may pick for one academic year.
///
/// The Classes screen browses with "load more"; the pickers on Attendance,
/// the timetable editor, Create Homework, announcements, student enrolment and
/// exams need the whole list, or a school with more than 20 sections loses
/// some of them. The backend decides what "every class" means: all of them for
/// an admin, the assigned ones for a teacher.
final classOptionsProvider =
    FutureProvider.autoDispose.family<List<ClassModel>, String>((ref, academicYear) async {
  final apiClient = ref.watch(apiClientProvider);
  return fetchAllPages(
    apiClient.dio,
    ApiEndpoints.classes,
    queryParameters: {'academic_year': academicYear},
    fromJson: ClassModel.fromJson,
    idOf: (item) => item.id,
  );
});

/// The current academic year's classes - what almost every picker wants.
final currentClassOptionsProvider = Provider.autoDispose<AsyncValue<List<ClassModel>>>(
  (ref) => ref.watch(classOptionsProvider(AppConstants.currentAcademicYear)),
);
