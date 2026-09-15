import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/staff_model.dart';

/// Teachers in the school, for the admin's "assign teacher to class" picker.
/// Admin-only on the backend; other roles get 403.
final teachersProvider = FutureProvider<List<StaffModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.schoolStaff,
    queryParameters: {'role': 'TEACHER'},
  );
  final data = response.data;
  final rows = data is List ? data : (data['results'] ?? []);
  return (rows as List).map((row) => StaffModel.fromJson(row)).toList();
});

/// Parents in the school, for the admin's "link parent to student" picker.
final parentsProvider = FutureProvider<List<StaffModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(
    ApiEndpoints.schoolStaff,
    queryParameters: {'role': 'PARENT'},
  );
  final data = response.data;
  final rows = data is List ? data : (data['results'] ?? []);
  return (rows as List).map((row) => StaffModel.fromJson(row)).toList();
});
