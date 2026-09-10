import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/school_providers.dart';
import '../../homework/presentation/create_homework_screen.dart';
import '../../school/presentation/students_screen.dart';
import '../presentation/main_nav_scaffold.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final classesAsync = ref.watch(classesProvider);
    final studentsAsync = ref.watch(studentsProvider);
    final homeworkAsync = ref.watch(homeworkProvider);
    final announcementsAsync = ref.watch(announcementsProvider);

    final classCount = classesAsync.value?.length ?? 0;
    final studentCount = studentsAsync.value?.length ?? 0;
    final homeworkCount = homeworkAsync.value?.length ?? 0;
    final announcementCount = announcementsAsync.value?.length ?? 0;

    final displayName = (user != null && user.fullName.trim().isNotEmpty)
        ? user.fullName.trim().split(' ').first
        : (user?.email.split('@').first ?? 'Teacher');
    final schoolName = user?.schoolName ?? AppConstants.schoolFullName;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Clean Header: Dashboard & School Badge
          const Text(
            'Teacher Dashboard',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'My Teaching Overview • Welcome back, $displayName!',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  AppConstants.schoolLogoPath,
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 14, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                schoolName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4 Stat Cards in 2x2 Grid (Live real counts from Django REST API)
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'My Classes',
                  count: '$classCount',
                  bgColor: AppColors.statClassesBg,
                  accentColor: AppColors.statClassesText,
                  icon: Icons.meeting_room_outlined,
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 1,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatCard(
                  title: 'Total Students',
                  count: '$studentCount',
                  bgColor: AppColors.statStudentsBg,
                  accentColor: AppColors.statStudentsText,
                  icon: Icons.groups_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: AppColors.background,
                          appBar: AppBar(
                            title: const Text('Students in My Classes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            backgroundColor: Colors.white,
                            elevation: 0,
                            iconTheme: const IconThemeData(color: AppColors.textPrimary),
                          ),
                          body: const StudentsScreen(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Homework',
                  count: '$homeworkCount',
                  bgColor: AppColors.statHomeworkBg,
                  accentColor: AppColors.statHomeworkText,
                  icon: Icons.description_outlined,
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 2,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatCard(
                  title: 'Announcements',
                  count: '$announcementCount',
                  bgColor: AppColors.statAnnouncementsBg,
                  accentColor: AppColors.statAnnouncementsText,
                  icon: Icons.campaign_outlined,
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Quick Actions Section
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  context: context,
                  label: '+ Create Homework',
                  icon: Icons.add_task,
                  bgColor: const Color(0xFFEEF2FF),
                  textColor: AppColors.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateHomeworkScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  context: context,
                  label: '+ Post Notice',
                  icon: Icons.campaign_outlined,
                  bgColor: const Color(0xFFF5F3FF),
                  textColor: const Color(0xFF7C3AED),
                  onTap: () {
                    ref.read(bottomNavIndexProvider.notifier).state = 3;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  context: context,
                  label: 'My Classes',
                  icon: Icons.meeting_room_outlined,
                  bgColor: const Color(0xFFF0FDFA),
                  textColor: const Color(0xFF0D9488),
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  context: context,
                  label: 'Students',
                  icon: Icons.people_outline,
                  bgColor: const Color(0xFFFFF7ED),
                  textColor: const Color(0xFFEA580C),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: AppColors.background,
                          appBar: AppBar(
                            title: const Text('Students in My Classes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            backgroundColor: Colors.white,
                            elevation: 0,
                            iconTheme: const IconThemeData(color: AppColors.textPrimary),
                          ),
                          body: const StudentsScreen(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          // Recent Announcements Section (Real API dynamic list)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Announcements',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          announcementsAsync.when(
            data: (list) {
              if (list.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Text(
                      'No announcements published yet.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                );
              }
              final recent = list.take(3).toList();
              return Column(
                children: recent.map((item) {
                  final isUrgent = item.isUrgent;
                  final isImportant = item.isImportant;
                  final color = isUrgent
                      ? AppColors.priorityUrgentText
                      : isImportant
                          ? AppColors.priorityImportantText
                          : AppColors.priorityNormalText;
                  final bg = isUrgent
                      ? AppColors.priorityUrgentBg
                      : isImportant
                          ? AppColors.priorityImportantBg
                          : AppColors.priorityNormalBg;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: _buildNoticeItem(
                      context: context,
                      title: item.title,
                      priority: item.priority,
                      priorityColor: color,
                      priorityBg: bg,
                      subtitle: item.audienceLabel,
                      date: '${item.publishedAt.day}/${item.publishedAt.month}/${item.publishedAt.year}',
                      icon: isUrgent ? Icons.campaign : Icons.notifications_none_rounded,
                      iconBg: bg,
                      iconColor: color,
                      onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 26),

          // Upcoming Homework Section (Real API dynamic list)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Upcoming Homework',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 2,
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          homeworkAsync.when(
            data: (hwList) {
              if (hwList.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Text(
                      'No homework assignments due.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                );
              }
              final recentHw = hwList.first;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.assignment_outlined,
                        color: Color(0xFF4F46E5),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recentHw.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${recentHw.subject} • ${recentHw.classroomName}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Due: ${recentHw.dueDate.day}/${recentHw.dueDate.month}/${recentHw.dueDate.year}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
        ],
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
                    width: 36,
                    height: 36,
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
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeItem({
    required BuildContext context,
    required String title,
    required String priority,
    required Color priorityColor,
    required Color priorityBg,
    required String subtitle,
    required String date,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: priorityBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            priority,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: priorityColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

