import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/student_model.dart';

/// The children linked to the signed-in parent, and which one is selected.

class ParentChildrenNotifier extends StateNotifier<AsyncValue<List<StudentModel>>> {
  final ApiClient apiClient;

  ParentChildrenNotifier(this.apiClient) : super(const AsyncValue.loading()) {
    loadChildren();
  }

  Future<void> loadChildren() async {
    state = const AsyncValue.loading();
    try {
      final response = await apiClient.dio.get(ApiEndpoints.parentChildren);
      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final children = results.map((item) => StudentModel.fromJson(item)).toList();
      state = AsyncValue.data(children);
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  void refresh() {
    loadChildren();
  }
}

final parentChildrenProvider = StateNotifierProvider<ParentChildrenNotifier,
    AsyncValue<List<StudentModel>>>((ref) {
  return ParentChildrenNotifier(ref.watch(apiClientProvider));
});

final selectedParentChildProvider = StateProvider<StudentModel?>((ref) => null);
