import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/notification_model.dart';

/// In-app notification list and the unread badge count.

class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final ApiClient apiClient;
  final Ref ref;

  NotificationsNotifier(this.apiClient, this.ref)
      : super(const AsyncValue.loading()) {
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    state = const AsyncValue.loading();
    try {
      final response = await apiClient.dio.get(ApiEndpoints.notifications);
      final List<dynamic> results =
          response.data is List ? response.data : (response.data['results'] ?? []);
      final notifications =
          results.map((item) => NotificationModel.fromJson(item)).toList();
      state = AsyncValue.data(notifications);
      await ref.read(unreadNotificationsCountProvider.notifier).fetchCount();
    } catch (e, st) {
      state = AsyncValue.error(apiClient.handleError(e).message, st);
    }
  }

  Future<bool> markAsRead(int notificationId) async {
    try {
      final response =
          await apiClient.dio.post(ApiEndpoints.notificationRead(notificationId));
      if (response.statusCode == 200) {
        state.whenData((list) {
          state = AsyncValue.data(
            list.map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n).toList(),
          );
        });
        ref.read(unreadNotificationsCountProvider.notifier).decrement();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      final response =
          await apiClient.dio.post(ApiEndpoints.notificationsMarkAllRead);
      if (response.statusCode == 200) {
        state.whenData((list) {
          state = AsyncValue.data(
            list.map((n) => n.copyWith(isRead: true)).toList(),
          );
        });
        ref.read(unreadNotificationsCountProvider.notifier).reset();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void refresh() {
    loadNotifications();
  }
}

final notificationsProvider = StateNotifierProvider<NotificationsNotifier,
    AsyncValue<List<NotificationModel>>>((ref) {
  return NotificationsNotifier(ref.watch(apiClientProvider), ref);
});

class UnreadNotificationsCountNotifier extends StateNotifier<int> {
  final ApiClient apiClient;

  UnreadNotificationsCountNotifier(this.apiClient) : super(0) {
    fetchCount();
  }

  Future<void> fetchCount() async {
    try {
      final response =
          await apiClient.dio.get(ApiEndpoints.notificationsUnreadCount);
      if (response.statusCode == 200 && response.data != null) {
        final count = response.data['unread_count'] as int? ?? 0;
        state = count;
      }
    } catch (_) {}
  }

  void decrement() {
    if (state > 0) state = state - 1;
  }

  void reset() {
    state = 0;
  }
}

final unreadNotificationsCountProvider =
    StateNotifierProvider<UnreadNotificationsCountNotifier, int>((ref) {
  return UnreadNotificationsCountNotifier(ref.watch(apiClientProvider));
});
