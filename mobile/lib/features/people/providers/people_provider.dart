import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/page_result.dart';
import '../../auth/models/staff_model.dart';
import '../../auth/providers/staff_provider.dart';

/// What the admin needs to hand a new person their login.
class IssuedLogin {
  const IssuedLogin({required this.account, required this.temporaryPassword});

  final StaffModel account;
  final String temporaryPassword;
}

/// Result of an admin action: either a value or a message to show.
class PeopleActionResult<T> {
  const PeopleActionResult.ok(this.value) : error = null;
  const PeopleActionResult.failed(this.error) : value = null;

  final T? value;
  final String? error;

  bool get isOk => error == null;
}

/// The admin's list of teachers or parents - one notifier per role.
///
/// Paginated because a school has a thousand parents. Deactivated accounts are
/// listed too (greyed out), so a teacher who left can be found and restored.
class PeopleNotifier extends StateNotifier<AsyncValue<List<StaffModel>>> {
  PeopleNotifier(this.apiClient, this.ref, this.role) : super(const AsyncValue.loading()) {
    load();
  }

  final ApiClient apiClient;
  final Ref ref;

  /// 'TEACHER' or 'PARENT'.
  final String role;

  String _search = '';
  String? _nextPageUrl;
  bool _loadingMore = false;
  int _totalCount = 0;

  int get totalCount => _totalCount;
  bool get hasMore => _nextPageUrl != null;
  bool get isLoadingMore => _loadingMore;

  Future<void> load({String? search}) async {
    if (search != null) _search = search.trim();
    state = const AsyncValue.loading();
    try {
      final response = await apiClient.dio.get(
        ApiEndpoints.schoolStaff,
        queryParameters: {
          'role': role,
          'page': 1,
          'include_inactive': 1,
          if (_search.isNotEmpty) 'search': _search,
        },
      );
      final page = PageResult.parse(response.data, StaffModel.fromJson);
      _nextPageUrl = page.nextUrl;
      _totalCount = page.totalCount;
      if (!mounted) return;
      state = AsyncValue.data(page.items);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  Future<void> loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final response = await apiClient.dio.getUri(Uri.parse(url));
      final page = PageResult.parse(response.data, StaffModel.fromJson);
      _nextPageUrl = page.nextUrl;
      _totalCount = page.totalCount;
      if (!mounted) return;
      state = AsyncValue.data([...?state.value, ...page.items]);
    } catch (_) {
      // Keep what is on screen; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }

  Future<PeopleActionResult<IssuedLogin>> create({
    required String fullName,
    required String phoneNumber,
    String email = '',
  }) async {
    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.schoolStaff,
        data: {
          'full_name': fullName.trim(),
          'phone_number': phoneNumber.trim(),
          'email': email.trim(),
          'role': role,
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final issued = IssuedLogin(
        account: StaffModel.fromJson(Map<String, dynamic>.from(data['account'] as Map)),
        temporaryPassword: data['temporary_password'].toString(),
      );
      _refreshPickers();
      await load();
      return PeopleActionResult.ok(issued);
    } catch (e) {
      return PeopleActionResult.failed(apiClient.handleError(e).message);
    }
  }

  Future<PeopleActionResult<StaffModel>> update(
    int id, {
    String? fullName,
    String? phoneNumber,
    String? email,
    bool? isActive,
  }) async {
    try {
      final response = await apiClient.dio.patch(
        ApiEndpoints.staffDetail(id),
        data: {
          if (fullName != null) 'full_name': fullName.trim(),
          if (phoneNumber != null) 'phone_number': phoneNumber.trim(),
          if (email != null) 'email': email.trim(),
          if (isActive != null) 'is_active': isActive,
        },
      );
      final updated = StaffModel.fromJson(Map<String, dynamic>.from(response.data as Map));
      if (mounted) {
        state = AsyncValue.data([
          for (final person in state.value ?? const <StaffModel>[])
            person.id == id ? updated : person,
        ]);
      }
      _refreshPickers();
      return PeopleActionResult.ok(updated);
    } catch (e) {
      return PeopleActionResult.failed(apiClient.handleError(e).message);
    }
  }

  Future<PeopleActionResult<String>> resetPassword(int id) async {
    try {
      final response = await apiClient.dio.post(ApiEndpoints.staffResetPassword(id));
      return PeopleActionResult.ok(
        (response.data as Map)['temporary_password'].toString(),
      );
    } catch (e) {
      return PeopleActionResult.failed(apiClient.handleError(e).message);
    }
  }

  /// The class and student pickers cache their own lists.
  void _refreshPickers() {
    ref.invalidate(role == 'TEACHER' ? teachersProvider : parentsProvider);
  }
}

final peopleProvider =
    StateNotifierProvider.family<PeopleNotifier, AsyncValue<List<StaffModel>>, String>(
  (ref, role) => PeopleNotifier(ref.watch(apiClientProvider), ref, role),
);
