import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../attendance/screens/mark_attendance_screen.dart';
import '../../timetable/screens/timetable_editor_screen.dart';
import '../../timetable/screens/timetable_screen.dart';
import '../../classes/screens/classes_screen.dart';
import '../../students/screens/students_screen.dart';
import '../../homework/screens/homework_list_screen.dart';
import '../../announcements/screens/announcements_list_screen.dart';
import '../../notifications/screens/notifications_list_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../exams/screens/exams_screen.dart';
import '../../exams/screens/report_card_screen.dart';
import '../../people/screens/people_screen.dart';
import '../../students/providers/parent_children_provider.dart';
import 'teacher_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'parent_dashboard_screen.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class MainNavScaffold extends ConsumerWidget {
  const MainNavScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final user = ref.watch(authProvider).user;
    final isTeacher = user?.role == UserRole.teacher;
    final isParent = user?.role == UserRole.parent;
    final unreadNotifsCount = ref.watch(unreadNotificationsCountProvider);

    final Widget dashboard = user?.role == UserRole.admin
        ? const AdminDashboardScreen()
        : isParent
            ? const ParentDashboardScreen()
            : const TeacherDashboardScreen();

    final List<Widget> pages = isParent
        ? [
            dashboard,
            const HomeworkListScreen(),
            const AnnouncementsListScreen(),
            const NotificationsListScreen(),
            const ProfileScreen(),
          ]
        : isTeacher
            ? [
                dashboard,
                const ClassesScreen(),
                const HomeworkListScreen(),
                const AnnouncementsListScreen(),
                const ProfileScreen(),
              ]
            : [
                dashboard,
                const ClassesScreen(),
                const StudentsScreen(),
                const HomeworkListScreen(),
                const AnnouncementsListScreen(),
                const ProfileScreen(),
              ];

    final safeIndex =
        (currentIndex >= 0 && currentIndex < pages.length) ? currentIndex : 0;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        shape: Border(bottom: BorderSide(color: colors.outlineVariant, width: 1)),
        leading: Builder(
          builder: (btnCtx) => IconButton(
            icon: Icon(Icons.menu, color: colors.onSurface, size: 24),
            onPressed: () => Scaffold.of(btnCtx).openDrawer(),
          ),
        ),
        titleSpacing: 4,
        title: Row(
          children: [
            Image.asset(
              AppConstants.schoolLogoPath,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.school, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            // Expanded + ellipsis: strictly bounds the title within the available
            // toolbar width on narrow phones, completely preventing RenderFlex overflow.
            Expanded(
              child: Text(
                AppConstants.schoolName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: unreadNotifsCount > 0,
              label: Text('$unreadNotifsCount'),
              child: Icon(Icons.notifications_outlined,
                  color: colors.onSurface, size: 22),
            ),
            onPressed: () {
              if (isParent) {
                ref.read(bottomNavIndexProvider.notifier).state = 3;
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: colors.surface,
                      appBar: AppBar(
                        title: const Text('Notifications',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        backgroundColor: colors.surface,
                        elevation: 0,
                        iconTheme: IconThemeData(color: colors.onSurface),
                      ),
                      body: const NotificationsListScreen(),
                    ),
                  ),
                );
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'logout') {
                  ref.read(authProvider.notifier).logout();
                  context.go('/login');
                }
              },
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (user != null && user.fullName.trim().isNotEmpty)
                            ? user.fullName
                            : (user?.email ?? 'School User'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        user?.role.label ?? 'Portal',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      Text(
                        user?.schoolName ?? AppConstants.schoolFullName,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout,
                          size: 18, color: AppColors.statusOverdueText),
                      SizedBox(width: 8),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: AppColors.statusOverdueText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Avatar + caret only. The user's name, role and school are
              // shown in the menu this button opens, so repeating them in the
              // toolbar just squeezed the title off the screen.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(
                    radius: 16,
                    initials: user?.initials ?? '?',
                    imageUrl: user?.avatarUrl,
                  ),
                  const Icon(Icons.arrow_drop_down,
                      color: AppColors.textSecondary, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
      drawer: _buildSideDrawer(context, ref, safeIndex, unreadNotifsCount),
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant, width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: safeIndex,
            onTap: (index) {
              ref.read(bottomNavIndexProvider.notifier).state = index;
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: colors.surface,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textMuted,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            elevation: 0,
            items: isParent
                ? [
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined),
                      activeIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.description_outlined),
                      activeIcon: Icon(Icons.description),
                      label: 'Homework',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.campaign_outlined),
                      activeIcon: Icon(Icons.campaign),
                      label: 'Notices',
                    ),
                    BottomNavigationBarItem(
                      icon: Badge(
                        isLabelVisible: unreadNotifsCount > 0,
                        label: Text('$unreadNotifsCount'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                      activeIcon: Badge(
                        isLabelVisible: unreadNotifsCount > 0,
                        label: Text('$unreadNotifsCount'),
                        child: const Icon(Icons.notifications),
                      ),
                      label: 'Alerts',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person),
                      label: 'Profile',
                    ),
                  ]
                : isTeacher
                    ? const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.home_outlined),
                          activeIcon: Icon(Icons.home),
                          label: 'Home',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.meeting_room_outlined),
                          activeIcon: Icon(Icons.meeting_room),
                          label: 'Classes',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.description_outlined),
                          activeIcon: Icon(Icons.description),
                          label: 'Homework',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.campaign_outlined),
                          activeIcon: Icon(Icons.campaign),
                          label: 'Notices',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.person_outline),
                          activeIcon: Icon(Icons.person),
                          label: 'Profile',
                        ),
                      ]
                    : [
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.home_outlined),
                          activeIcon: Icon(Icons.home),
                          label: 'Home',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.meeting_room_outlined),
                          activeIcon: Icon(Icons.meeting_room),
                          label: 'Classes',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.people_outline),
                          activeIcon: Icon(Icons.people),
                          label: 'Students',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.description_outlined),
                          activeIcon: Icon(Icons.description),
                          label: 'Homework',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.campaign_outlined),
                          activeIcon: Icon(Icons.campaign),
                          label: 'Notices',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.person_outline),
                          activeIcon: Icon(Icons.person),
                          label: 'Profile',
                        ),
                      ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideDrawer(BuildContext context, WidgetRef ref, int currentIndex,
      int unreadNotifsCount) {
    final user = ref.watch(authProvider).user;
    final isTeacher = user?.role == UserRole.teacher;
    final isParent = user?.role == UserRole.parent;

    return Drawer(
      child: Container(
        color: AppColors.textPrimary,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 18.0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          AppConstants.schoolLogoPath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.school,
                              color: AppColors.primary, size: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.schoolName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '${AppConstants.schoolBranch} • Since 1999',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              // Scrolls: with exams and people added, a short phone cannot
              // fit every entry, and a Column here would overflow.
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 12),
                  children: [
                    _drawerItem(
                      title: 'Dashboard',
                      icon: Icons.dashboard_outlined,
                      isActive: currentIndex == 0,
                      onTap: () {
                        ref.read(bottomNavIndexProvider.notifier).state = 0;
                        Navigator.pop(context);
                      },
                    ),
                    if (isParent) ...[
                      _drawerItem(
                        title: 'Homework',
                        icon: Icons.assignment_outlined,
                        isActive: currentIndex == 1,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 1;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Report card',
                        icon: Icons.workspace_premium_outlined,
                        isActive: false,
                        onTap: () {
                          Navigator.pop(context);
                          _openReportCard(context, ref);
                        },
                      ),
                      _drawerItem(
                        title: 'Notices',
                        icon: Icons.campaign_outlined,
                        isActive: currentIndex == 2,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 2;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Notifications',
                        icon: Icons.notifications_outlined,
                        isActive: currentIndex == 3,
                        badgeCount: unreadNotifsCount,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 3;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Profile',
                        icon: Icons.person_outline,
                        isActive: currentIndex == 4,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 4;
                          Navigator.pop(context);
                        },
                      ),
                    ] else if (isTeacher) ...[
                      _drawerItem(
                        title: 'My Classes',
                        icon: Icons.meeting_room_outlined,
                        isActive: currentIndex == 1,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 1;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Timetable',
                        icon: Icons.schedule_outlined,
                        isActive: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => isTeacher
                                  ? const TimetableScreen.forTeacher()
                                  : const TimetableEditorScreen(),
                            ),
                          );
                        },
                      ),
                      _drawerItem(
                        title: 'Attendance',
                        icon: Icons.how_to_reg_outlined,
                        isActive: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const MarkAttendanceScreen()),
                          );
                        },
                      ),
                      _pushItem(
                        context,
                        title: 'Exams & Marks',
                        icon: Icons.fact_check_outlined,
                        builder: (_) => const ExamsScreen(),
                      ),
                      _drawerItem(
                        title: 'Students',
                        icon: Icons.people_outline,
                        isActive: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                backgroundColor: AppColors.background,
                                appBar: AppBar(
                                  title: const Text('Students in My Classes',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  backgroundColor: Colors.white,
                                  elevation: 0,
                                  iconTheme: const IconThemeData(
                                      color: AppColors.textPrimary),
                                ),
                                body: const StudentsScreen(),
                              ),
                            ),
                          );
                        },
                      ),
                      _drawerItem(
                        title: 'Homework',
                        icon: Icons.assignment_outlined,
                        isActive: currentIndex == 2,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 2;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Notices',
                        icon: Icons.campaign_outlined,
                        isActive: currentIndex == 3,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 3;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Profile',
                        icon: Icons.person_outline,
                        isActive: currentIndex == 4,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 4;
                          Navigator.pop(context);
                        },
                      ),
                    ] else ...[
                      _drawerItem(
                        title: 'Classes',
                        icon: Icons.meeting_room_outlined,
                        isActive: currentIndex == 1,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 1;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Students',
                        icon: Icons.people_outline,
                        isActive: currentIndex == 2,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 2;
                          Navigator.pop(context);
                        },
                      ),
                      _pushItem(
                        context,
                        title: 'Teachers & Parents',
                        icon: Icons.badge_outlined,
                        builder: (_) => const PeopleScreen(),
                      ),
                      _pushItem(
                        context,
                        title: 'Timetable',
                        icon: Icons.schedule_outlined,
                        builder: (_) => const TimetableEditorScreen(),
                      ),
                      _pushItem(
                        context,
                        title: 'Exams & Results',
                        icon: Icons.fact_check_outlined,
                        builder: (_) => const ExamsScreen(),
                      ),
                      _drawerItem(
                        title: 'Homework',
                        icon: Icons.assignment_outlined,
                        isActive: currentIndex == 3,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 3;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Notices',
                        icon: Icons.campaign_outlined,
                        isActive: currentIndex == 4,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 4;
                          Navigator.pop(context);
                        },
                      ),
                      _drawerItem(
                        title: 'Profile',
                        icon: Icons.person_outline,
                        isActive: currentIndex == 5,
                        onTap: () {
                          ref.read(bottomNavIndexProvider.notifier).state = 5;
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                leading: const Icon(Icons.logout,
                    color: AppColors.textMuted, size: 20),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: AppColors.divider,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(authProvider.notifier).logout();
                  context.go('/login');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the report card of the child the parent is looking at, or asks
  /// which child when there is more than one.
  Future<void> _openReportCard(BuildContext context, WidgetRef ref) async {
    final children = ref.read(parentChildrenProvider).value ?? const [];
    final selected = ref.read(selectedParentChildProvider);
    var studentId =
        selected?.id ?? (children.length == 1 ? children.first.id : null);

    if (studentId == null && children.isNotEmpty) {
      studentId = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.white,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Whose report card?',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
              for (final child in children)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(child.fullName),
                  subtitle: Text(child.className),
                  onTap: () => Navigator.pop(sheetContext, child.id),
                ),
            ],
          ),
        ),
      );
    }
    if (studentId == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ReportCardScreen(studentId: studentId!)),
    );
  }

  Widget _pushItem(BuildContext context,
      {required String title,
      required IconData icon,
      required WidgetBuilder builder}) {
    return _drawerItem(
      title: title,
      icon: icon,
      isActive: false,
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: builder));
      },
    );
  }

  Widget _drawerItem({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? AppColors.englishIconColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(icon,
              color: isActive ? Colors.white : AppColors.textMuted, size: 20),
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFFCBD5E1),
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          trailing: (badgeCount != null && badgeCount > 0)
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.mathIconColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                )
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}
