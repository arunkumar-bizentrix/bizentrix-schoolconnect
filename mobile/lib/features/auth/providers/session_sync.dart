import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../announcements/providers/announcements_provider.dart';
import '../../classes/providers/class_options_provider.dart';
import '../../classes/providers/classes_provider.dart';
import '../../homework/providers/homework_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../people/providers/people_provider.dart';
import '../../students/providers/parent_children_provider.dart';
import '../../students/providers/parent_today_provider.dart';
import '../../students/providers/students_provider.dart';
import 'staff_provider.dart';

/// Every provider that holds data belonging to one signed-in user.
///
/// Riverpod keeps a notifier alive for the life of the app and each of these
/// loads once, in its constructor. Without clearing them on a sign-in or
/// sign-out, the next account on the same device sees the previous account's
/// classes, homework and notifications until something happens to reload them
/// - a stale-data bug and a privacy leak at once.
///
/// Add to this list whenever a new provider caches per-user data.
final List<ProviderOrFamily> userScopedProviders = <ProviderOrFamily>[
  classesProvider,
  classOptionsProvider,
  studentsProvider,
  homeworkProvider,
  announcementsProvider,
  notificationsProvider,
  unreadNotificationsCountProvider,
  parentChildrenProvider,
  selectedParentChildProvider,
  parentTodayProvider,
  peopleProvider,
  teachersProvider,
  parentsProvider,
];

/// Drops every cached per-user list. Safe to call with a [WidgetRef] or a
/// [ProviderContainer]; both expose `invalidate`.
void invalidateUserScopedProviders(WidgetRef ref) {
  for (final provider in userScopedProviders) {
    ref.invalidate(provider);
  }
}
