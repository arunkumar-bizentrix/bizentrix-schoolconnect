import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/school_providers.dart';
import '../../school/presentation/classes_screen.dart';
import '../../school/presentation/students_screen.dart';
import '../../homework/presentation/homework_list_screen.dart';
import '../../announcements/presentation/announcements_list_screen.dart';
import 'teacher_dashboard_screen.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class MainNavScaffold extends ConsumerWidget {
  const MainNavScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final user = ref.watch(authProvider).user;

    final List<Widget> pages = const [
      TeacherDashboardScreen(),
      ClassesScreen(),
      StudentsScreen(),
      HomeworkListScreen(),
      AnnouncementsListScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        shape: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
        leading: Builder(
          builder: (btnCtx) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textPrimary, size: 24),
            onPressed: () => Scaffold.of(btnCtx).openDrawer(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'logout') {
                  ref.read(authProvider.notifier).logout();
                  context.go('/login');
                }
              },
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.fullName ?? 'Priya Sharma',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        user?.schoolName ?? 'ABC Matriculation School',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18, color: AppColors.statusOverdueText),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 17,
                    backgroundImage: NetworkImage(
                      'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        user?.fullName ?? 'Priya Sharma',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Text(
                        'Teacher',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      drawer: _buildSideDrawer(context, ref, currentIndex),
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (index) {
              ref.read(bottomNavIndexProvider.notifier).state = index;
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: const Color(0xFF94A3B8),
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            elevation: 0,
            items: const [
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
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Students',
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideDrawer(BuildContext context, WidgetRef ref, int currentIndex) {
    return Drawer(
      child: Container(
        color: const Color(0xFF0F172A), // Dark navy slate matching mockup
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drawer Header with SchoolConnect Logo
              Padding(
                padding: const EdgeInsets.all(22.0),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'SchoolConnect',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              const SizedBox(height: 12),

              // Drawer Nav Items
              _drawerItem(
                title: 'Dashboard',
                icon: Icons.dashboard_outlined,
                isActive: currentIndex == 0,
                onTap: () {
                  ref.read(bottomNavIndexProvider.notifier).state = 0;
                  Navigator.pop(context);
                },
              ),
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
                title: 'Announcements',
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
                isActive: false,
                onTap: () {
                  Navigator.pop(context);
                },
              ),

              const Spacer(),
              const Divider(color: Color(0xFF1E293B), height: 1),

              // Logout at Bottom
              ListTile(
                leading: const Icon(Icons.logout, color: Color(0xFF94A3B8), size: 20),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
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

  Widget _drawerItem({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: isActive ? Colors.white : const Color(0xFF94A3B8), size: 20),
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFFCBD5E1),
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
