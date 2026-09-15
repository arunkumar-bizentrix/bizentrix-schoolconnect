import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/monitoring_models.dart';

Map<String, dynamic> _asMap(dynamic data) => Map<String, dynamic>.from(data as Map);

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.dio.get(
    ApiEndpoints.dashboardSummary,
    queryParameters: {'academic_year': AppConstants.currentAcademicYear},
  );
  return DashboardSummary(_asMap(response.data));
});

final studentProfileProvider = FutureProvider.autoDispose.family<StudentProfile, int>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  return StudentProfile(_asMap((await api.dio.get(ApiEndpoints.studentProfile(id))).data));
});

final classOverviewProvider = FutureProvider.autoDispose.family<ClassOverview, int>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  return ClassOverview(_asMap((await api.dio.get(ApiEndpoints.classOverview(id))).data));
});

final teacherProfileProvider = FutureProvider.autoDispose.family<TeacherProfile, int>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  return TeacherProfile(_asMap((await api.dio.get(ApiEndpoints.teacherProfile(id))).data));
});
