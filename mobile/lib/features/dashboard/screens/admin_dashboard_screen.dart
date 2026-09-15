import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../exams/screens/exams_screen.dart';
import '../../people/screens/people_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../announcements/models/announcement_model.dart';
import '../../announcements/providers/announcements_provider.dart';
import '../../announcements/screens/announcement_detail_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/classes_provider.dart';
import '../../homework/models/homework_model.dart';
import '../../homework/providers/homework_provider.dart';
import '../../students/providers/students_provider.dart';
import 'main_nav_scaffold.dart';

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

    final schoolFullName = (user?.schoolName != null && user!.schoolName!.isNotEmpty)
        ? user.schoolName!
        : AppConstants.schoolFullName;

    final totalStudents = studentsAsync.value?.length.toString() ?? '0';
    final totalClasses = classesAsync.value?.length.toString() ?? '0';
    final totalHomework = homeworkAsync.value?.length.toString() ?? '0';
    final totalNotices = announcementsAsync.value?.length.toString() ?? '0';

    final adminName = (user != null && user.fullName.trim().isNotEmpty)
        ? user.fullName.trim()
        : 'Administrator';

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.read(studentsProvider.notifier).refresh();
        ref.read(classesProvider.notifier).refresh();
        ref.read(homeworkProvider.notifier).refresh();
        ref.read(announcementsProvider.notifier).refresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Premium School Identity Hero Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1E1B4B), // Deep Indigo
                    Color(0xFF312E81), // Royal Indigo
                    Color(0xFF4338CA), // Vibrant Indigo
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF312E81).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges: Admin Portal & Academic Year
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Admin Portal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 12, color: Colors.white70),
                            SizedBox(width: 5),
                            Text(
                              AppConstants.currentAcademicYear,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // School Name - full width, unclipped
                  Text(
                    schoolFullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppConstants.schoolTagline} • ${AppConstants.schoolEstablished}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  // Bottom status row
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4ADE80), // Bright green
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Live Data',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Admin: $adminName',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Live Institution Metrics (4 Interactive Stat Cards)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Live Institution Metrics',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Tap to view',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Total Students',
                    count: totalStudents,
                    bgColor: AppColors.statStudentsBg,
                    accentColor: AppColors.statStudentsText,
                    icon: Icons.groups_outlined,
                    onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Active Classes',
                    count: totalClasses,
                    bgColor: AppColors.statClassesBg,
                    accentColor: AppColors.statClassesText,
                    icon: Icons.meeting_room_outlined,
                    onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Homework Set',
                    count: totalHomework,
                    bgColor: AppColors.statHomeworkBg,
                    accentColor: AppColors.statHomeworkText,
                    icon: Icons.description_outlined,
                    onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Circulars',
                    count: totalNotices,
                    bgColor: AppColors.statAnnouncementsBg,
                    accentColor: AppColors.statAnnouncementsText,
                    icon: Icons.campaign_outlined,
                    onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Administrative Actions
            Text(
              'Administrative Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              icon: Icons.badge_rounded,
              title: 'Teachers & Parents',
              subtitle: 'Add a teacher, reset a password, deactivate someone who left',
              color: AppColors.roleAdmin,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PeopleScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.fact_check_rounded,
              title: 'Exams & Results',
              subtitle: 'Set exams, follow marks entry, publish results to parents',
              color: AppColors.statAnnouncementsText,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExamsScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.campaign_rounded,
              title: 'Broadcast Announcement',
              subtitle: 'Send instant circular to parents or teachers',
              color: AppColors.accent,
              onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.menu_book_rounded,
              title: 'Manage Homework',
              subtitle: 'Review assignments and submissions across classes',
              color: AppColors.primary,
              onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Student Directory',
              subtitle: 'Enroll and manage students in school classes',
              color: AppColors.roleParent,
              onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 2,
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.meeting_room_rounded,
              title: 'Class Overview',
              subtitle: 'Review class sections, subjects, and teachers',
              color: AppColors.secondary,
              onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 1,
            ),
            const SizedBox(height: 24),

            // Recent Circulars Live Overview
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Recent Circulars',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            announcementsAsync.when(
              data: (notices) {
                if (notices.isEmpty) {
                  return _buildEmptySection(
                    icon: Icons.campaign_outlined,
                    message: 'No circulars published yet',
                  );
                }
                final recentNotices = notices.take(2).toList();
                return Column(
                  children: recentNotices.map((n) => _buildNoticePreview(context, n)).toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, __) => _buildEmptySection(
                icon: Icons.info_outline,
                message: 'Could not load circulars',
              ),
            ),
            const SizedBox(height: 20),

            // Recent Homework Live Overview
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Active Homework',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            homeworkAsync.when(
              data: (hwList) {
                if (hwList.isEmpty) {
                  return _buildEmptySection(
                    icon: Icons.description_outlined,
                    message: 'No homework assignments created yet',
                  );
                }
                final recentHw = hwList.take(2).toList();
                return Column(
                  children: recentHw.map((hw) => _buildHomeworkPreview(context, ref, hw)).toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, __) => _buildEmptySection(
                icon: Icons.info_outline,
                message: 'Could not load homework',
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String count,
    required Color bgColor,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  Flexible(
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        height: 1.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: AppColors.textMuted.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppColors.textMuted,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildNoticePreview(BuildContext context, AnnouncementModel notice) {
    Color priorityColor = AppColors.priorityNormalText;
    Color priorityBg = AppColors.priorityNormalBg;
    if (notice.priority == 'URGENT') {
      priorityColor = AppColors.priorityUrgentText;
      priorityBg = AppColors.priorityUrgentBg;
    } else if (notice.priority == 'IMPORTANT') {
      priorityColor = AppColors.priorityImportantText;
      priorityBg = AppColors.priorityImportantBg;
    }

    final dateStr = DateFormat('dd MMM yyyy').format(notice.publishedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: priorityBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.campaign, color: priorityColor, size: 20),
        ),
        title: Text(
          notice.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$dateStr • ${notice.audienceLabel}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: priorityBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            notice.priority,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: priorityColor,
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AnnouncementDetailScreen(announcement: notice),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHomeworkPreview(BuildContext context, WidgetRef ref, HomeworkModel hw) {
    final dueDateStr = DateFormat('dd MMM').format(hw.dueDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.statHomeworkBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.assignment_outlined, color: AppColors.statHomeworkText, size: 20),
        ),
        title: Text(
          hw.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${hw.subject} • ${hw.className}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Due $dueDateStr',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
      ),
    );
  }

  Widget _buildEmptySection({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
