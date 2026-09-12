import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../announcements/providers/announcements_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/classes_provider.dart';
import '../../homework/providers/homework_provider.dart';
import '../../students/providers/students_provider.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final classesAsync = ref.watch(classesProvider);
    final studentsAsync = ref.watch(studentsProvider);
    final homeworkAsync = ref.watch(homeworkProvider);
    final announcementsAsync = ref.watch(announcementsProvider);

    final schoolName = (user?.schoolName != null && user!.schoolName!.isNotEmpty)
        ? user.schoolName!
        : 'Bizentrix SchoolConnect';

    final totalStudents = studentsAsync.value?.length.toString() ?? '0';
    final totalClasses = classesAsync.value?.length.toString() ?? '0';
    final totalHomework = homeworkAsync.value?.length.toString() ?? '0';
    final totalNotices = announcementsAsync.value?.length.toString() ?? '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/announcements'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // School Banner Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.roleAdmin, Color(0xFF4C1D95)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          schoolName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Admin Portal',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Academic Session: ${AppConstants.currentAcademicYear}',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Metric Summary Cards (Real API Data)
            Text('Live Institution Metrics', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard(context, 'Total Students', totalStudents, Icons.people_outline, AppColors.primary),
                const SizedBox(width: 12),
                _buildMetricCard(context, 'Classes', totalClasses, Icons.meeting_room_outlined, AppColors.secondary),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard(context, 'Homework', totalHomework, Icons.assignment_outlined, AppColors.roleTeacher),
                const SizedBox(width: 12),
                _buildMetricCard(context, 'Notices', totalNotices, Icons.campaign_outlined, AppColors.accent),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Text('Administrative Actions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              icon: Icons.campaign_rounded,
              title: 'Broadcast Announcement',
              subtitle: 'Send instant circular to parents or teachers',
              color: AppColors.accent,
              onTap: () => context.push('/announcements'),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              context: context,
              icon: Icons.menu_book_rounded,
              title: 'Manage Homework',
              subtitle: 'Review assignments and submissions across classes',
              color: AppColors.primary,
              onTap: () => context.push('/homework'),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              context: context,
              icon: Icons.person_add_alt_1_rounded,
              title: 'Student Directory',
              subtitle: 'Enroll and manage students in school classes',
              color: AppColors.roleParent,
              onTap: () => context.push('/students'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String label,
    String count,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                count,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
