import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/school_providers.dart';
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

    final classCount = classesAsync.value?.length ?? 2;
    final studentCount = studentsAsync.value?.length ?? 48;
    final homeworkCount = homeworkAsync.value?.length ?? 5;
    final announcementCount = announcementsAsync.value?.length ?? 3;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Dashboard / Welcome back, Priya!
          const Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Welcome back, ${user?.fullName.split(' ').first ?? 'Priya'}!',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),

          // 4 Stat Cards in 2x2 Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'My Classes',
                  count: '$classCount',
                  bgColor: AppColors.statClassesBg,
                  accentColor: AppColors.statClassesText,
                  icon: Icons.person_outline,
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
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 2,
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
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 3,
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
                  onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          // Recent Announcements Section
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
                onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
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

          // Notice 1: School Reopens (URGENT)
          _buildNoticeItem(
            context: context,
            title: 'School Reopens - Important Notice',
            priority: 'URGENT',
            priorityColor: AppColors.priorityUrgentText,
            priorityBg: AppColors.priorityUrgentBg,
            subtitle: 'For All Students & Parents',
            date: 'Aug 25, 2025',
            icon: Icons.campaign,
            iconBg: AppColors.statHomeworkBg,
            iconColor: AppColors.statHomeworkText,
            onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
          ),
          const SizedBox(height: 10),

          // Notice 2: Annual Sports Day (IMPORTANT)
          _buildNoticeItem(
            context: context,
            title: 'Annual Sports Day',
            priority: 'IMPORTANT',
            priorityColor: AppColors.priorityImportantText,
            priorityBg: AppColors.priorityImportantBg,
            subtitle: 'For All Students',
            date: 'Aug 22, 2025',
            icon: Icons.description_outlined,
            iconBg: AppColors.statHomeworkBg,
            iconColor: AppColors.statHomeworkText,
            onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
          ),
          const SizedBox(height: 10),

          // Notice 3: PTA Meeting (NORMAL)
          _buildNoticeItem(
            context: context,
            title: 'PTA Meeting',
            priority: 'NORMAL',
            priorityColor: AppColors.priorityNormalText,
            priorityBg: AppColors.priorityNormalBg,
            subtitle: 'For Parents',
            date: 'Aug 20, 2025',
            icon: Icons.campaign_outlined,
            iconBg: AppColors.statHomeworkBg,
            iconColor: AppColors.statHomeworkText,
            onTap: () => ref.read(bottomNavIndexProvider.notifier).state = 4,
          ),
          const SizedBox(height: 26),

          // Upcoming Homework Section
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

          // Upcoming Homework Item
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
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
                    children: const [
                      Text(
                        'Mathematics - Chapter 5',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Grade 5 - A',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Due: Aug 28, 2025',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
}
