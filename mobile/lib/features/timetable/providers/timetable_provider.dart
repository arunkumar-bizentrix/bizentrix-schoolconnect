import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/timetable_model.dart';

/// One class's weekly timetable. A parent may only ask for a class one of
/// their children is in; the backend returns 403 otherwise.
final classTimetableProvider =
    FutureProvider.family<TimetableWeek, int>((ref, classId) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.timetableWeek,
    queryParameters: {'class_id': classId},
  );
  return TimetableWeek.fromJson(Map<String, dynamic>.from(response.data as Map));
});

/// The signed-in teacher's own week: where they are meant to be, each period.
final myTimetableProvider = FutureProvider<TimetableWeek>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.timetableMine);
  return TimetableWeek.fromJson(Map<String, dynamic>.from(response.data as Map));
});
