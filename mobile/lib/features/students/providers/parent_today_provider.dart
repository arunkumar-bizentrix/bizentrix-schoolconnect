import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/child_today.dart';

/// The parent's Today view for every linked child, in one request.
final parentTodayProvider = FutureProvider<List<ChildToday>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get(ApiEndpoints.parentToday);
  final data = Map<String, dynamic>.from(response.data as Map);
  return (data['children'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ChildToday.fromJson)
      .toList();
});
