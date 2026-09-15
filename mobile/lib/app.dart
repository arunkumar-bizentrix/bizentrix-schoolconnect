import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'core/push/push_service.dart';
import 'core/routing/app_router.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/providers/session_sync.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'core/theme/app_theme.dart';

class SchoolConnectApp extends ConsumerStatefulWidget {
  const SchoolConnectApp({super.key});

  @override
  ConsumerState<SchoolConnectApp> createState() => _SchoolConnectAppState();
}

class _SchoolConnectAppState extends ConsumerState<SchoolConnectApp> {
  final List<StreamSubscription<dynamic>> _pushSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _listenForPush();
  }

  /// Keeps the in-app list in step with the phone's notification tray.
  ///
  /// A push that arrives while the app is open is delivered to the app, not
  /// the tray - without this the parent gets nothing until they pull to
  /// refresh. Tapping a tray notification lands here too, so the list they
  /// open is already current.
  void _listenForPush() {
    final push = ref.read(pushServiceProvider);
    if (!push.isAvailable) return;

    void refresh(dynamic _) {
      if (!mounted) return;
      ref.read(notificationsProvider.notifier).refresh();
    }

    _pushSubscriptions
      ..add(push.onForegroundMessage.listen(refresh))
      ..add(push.onNotificationTapped.listen(refresh));
  }

  @override
  void dispose() {
    for (final subscription in _pushSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // When the signed-in user changes, drop every cached per-user list.
    // Without this, signing out and signing in as someone else on the same
    // device shows the previous account's data until each screen reloads.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.user?.id == next.user?.id) return;
      invalidateUserScopedProviders(ref);
    });

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) {
        // Native mobile gets the exact device screen and untouched gesture system
        if (!kIsWeb) {
          return child ?? const SizedBox.shrink();
        }
        // Web gets centered mobile frame
        return Container(
          color: const Color(0xFF0F172A),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: child,
          ),
        );
      },
    );
  }
}
