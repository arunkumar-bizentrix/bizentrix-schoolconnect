import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/school_providers.dart';
import '../../school/models/student_model.dart';
import '../../homework/models/homework_model.dart';
import '../../announcements/models/announcement_model.dart';
import 'main_nav_scaffold.dart';

class ParentDashboardScreen extends ConsumerWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final childrenAsync = ref.watch(parentChildrenProvider);
    final selectedChild = ref.watch(selectedParentChildProvider);
    final homeworkAsync = ref.watch(homeworkProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final unreadNotifsCount = ref.watch(unreadNotificationsCountProvider);

    final parentName = (user != null && user.fullName.trim().isNotEmpty)
        ? user.fullName.trim()
        : (user?.email.split('@').first ?? 'Parent');

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(parentChildrenProvider.notifier).refresh();
        ref.read(homeworkProvider.notifier).refresh();
        ref.read(announcementsProvider.notifier).refresh();
        ref.read(notificationsProvider.notifier).refresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parent Portal',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Welcome back, $parentName',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Parent Verified',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Unread Notifications Banner (Clickable to switch to Notifications tab)
            if (unreadNotifsCount > 0) ...[
              InkWell(
                onTap: () {
                  ref.read(bottomNavIndexProvider.notifier).state = 3;
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$unreadNotifsCount new notification${unreadNotifsCount > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Tap here to view latest homework & school circulars.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ═══════════════════════════════════════════════
            // MY CHILDREN SECTION
            // ═══════════════════════════════════════════════
            childrenAsync.when(
              data: (children) {
                if (children.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.family_restroom_rounded, size: 40, color: Color(0xFF94A3B8)),
                        SizedBox(height: 10),
                        Text(
                          'No Children Linked Yet',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Please contact Vivekananda School Bagalur administration to link your student profile with this parent account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'My Children',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${children.length}',
                                style: const TextStyle(
                                  color: Color(0xFF166534),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (children.length > 1)
                          Text(
                            selectedChild != null ? 'Filtered: ${selectedChild.fullName}' : 'Showing: All',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Child filter chips if multiple children
                    if (children.length > 1) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: const Text('All Children'),
                                selected: selectedChild == null,
                                onSelected: (_) {
                                  ref.read(selectedParentChildProvider.notifier).state = null;
                                },
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selectedChild == null ? FontWeight.bold : FontWeight.normal,
                                  color: selectedChild == null ? Colors.white : AppColors.textSecondary,
                                ),
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: selectedChild == null ? AppColors.primary : AppColors.border,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                showCheckmark: false,
                              ),
                            ),
                            ...children.map((child) {
                              final isSelected = selectedChild?.id == child.id;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ChoiceChip(
                                  avatar: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: isSelected ? Colors.white24 : const Color(0xFFE2E8F0),
                                    child: Icon(
                                      Icons.person,
                                      size: 12,
                                      color: isSelected ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                  label: Text('${child.fullName} (${child.className})'),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    ref.read(selectedParentChildProvider.notifier).state = child;
                                  },
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.white : AppColors.textSecondary,
                                  ),
                                  backgroundColor: Colors.white,
                                  side: BorderSide(
                                    color: isSelected ? AppColors.primary : AppColors.border,
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  showCheckmark: false,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Children Cards Row / Column
                    ...children.map((child) => _buildChildCard(context, child, selectedChild?.id == child.id)),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),

            // ═══════════════════════════════════════════════
            // QUICK STATS OVERVIEW
            // ═══════════════════════════════════════════════
            _buildStatsGrid(
              ref: ref,
              childrenCount: childrenAsync.value?.length ?? 0,
              homeworkCount: homeworkAsync.value?.length ?? 0,
              announcementsCount: announcementsAsync.value?.length ?? 0,
              unreadNotifsCount: unreadNotifsCount,
            ),
            const SizedBox(height: 24),

            // ═══════════════════════════════════════════════
            // ASSIGNED HOMEWORK PREVIEW
            // ═══════════════════════════════════════════════
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Text(
                      'Assigned Homework',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    ref.read(bottomNavIndexProvider.notifier).state = 1;
                  },
                  child: const Text('View All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            homeworkAsync.when(
              data: (allHomework) {
                final filteredHomework = _filterHomeworkByChild(allHomework, selectedChild);

                if (filteredHomework.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.assignment_turned_in_outlined, size: 32, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 8),
                          Text(
                            selectedChild != null
                                ? 'No homework assigned for ${selectedChild.fullName}\'s class.'
                                : 'No homework assigned currently.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: filteredHomework.take(3).map((item) => _buildHomeworkCard(context, item, ref)).toList(),
                );
              },
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              error: (err, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // ═══════════════════════════════════════════════
            // SCHOOL NOTICES PREVIEW
            // ═══════════════════════════════════════════════
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'School Circulars & Notices',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(bottomNavIndexProvider.notifier).state = 2;
                  },
                  child: const Text('View All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            announcementsAsync.when(
              data: (allNotices) {
                final filteredNotices = _filterNoticesByChild(allNotices, selectedChild);

                if (filteredNotices.isEmpty) {
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
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                return Column(
                  children: filteredNotices.take(2).map((notice) => _buildNoticeCard(context, notice, ref)).toList(),
                );
              },
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChildCard(BuildContext context, StudentModel child, bool isHighlighted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted ? AppColors.primary : AppColors.border,
          width: isHighlighted ? 1.5 : 1,
        ),
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
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFFDCFCE7),
            child: Icon(Icons.child_care_rounded, color: Color(0xFF166534), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.fullName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Class: ${child.className}  •  Adm: ${child.admissionNumber}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'ENROLLED',
              style: TextStyle(
                color: Color(0xFF166534),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid({
    required WidgetRef ref,
    required int childrenCount,
    required int homeworkCount,
    required int announcementsCount,
    required int unreadNotifsCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildStatTile(
            title: 'Children',
            value: '$childrenCount',
            icon: Icons.family_restroom_rounded,
            iconBg: const Color(0xFFDCFCE7),
            iconColor: const Color(0xFF166534),
            onTap: null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatTile(
            title: 'Homework',
            value: '$homeworkCount',
            icon: Icons.assignment_outlined,
            iconBg: const Color(0xFFFEF3C7),
            iconColor: const Color(0xFFD97706),
            onTap: () {
              ref.read(bottomNavIndexProvider.notifier).state = 1;
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatTile(
            title: 'Notices',
            value: '$announcementsCount',
            icon: Icons.campaign_outlined,
            iconBg: const Color(0xFFEFF6FF),
            iconColor: AppColors.primary,
            onTap: () {
              ref.read(bottomNavIndexProvider.notifier).state = 2;
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatTile(
            title: 'Alerts',
            value: '$unreadNotifsCount',
            icon: Icons.notifications_outlined,
            iconBg: unreadNotifsCount > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
            iconColor: unreadNotifsCount > 0 ? AppColors.error : AppColors.textSecondary,
            onTap: () {
              ref.read(bottomNavIndexProvider.notifier).state = 3;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeworkCard(BuildContext context, HomeworkModel item, WidgetRef ref) {
    final isOverdue = item.isOverdue;
    final dueDateFormatted = DateFormat('MMM d, yyyy').format(item.dueDate);

    return InkWell(
      onTap: () {
        ref.read(bottomNavIndexProvider.notifier).state = 1;
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.subject,
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.classroomName,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOverdue ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: isOverdue ? AppColors.error : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isOverdue ? 'Overdue' : 'Due $dueDateFormatted',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isOverdue ? AppColors.error : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeCard(BuildContext context, AnnouncementModel notice, WidgetRef ref) {
    final isUrgent = notice.isUrgent;
    final publishedFormatted = DateFormat('MMM d, yyyy').format(notice.publishedAt);

    return InkWell(
      onTap: () {
        ref.read(bottomNavIndexProvider.notifier).state = 2;
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isUrgent ? const Color(0xFFFEE2E2) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    notice.priority,
                    style: TextStyle(
                      color: isUrgent ? AppColors.error : AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  notice.isClassTargeted
                      ? (notice.targetClassName ?? 'Class Notice')
                      : 'School-wide Notice',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  publishedFormatted,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notice.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              notice.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  List<HomeworkModel> _filterHomeworkByChild(List<HomeworkModel> list, StudentModel? child) {
    if (child == null) return list;
    return list.where((hw) {
      if (child.classId != null && hw.classroomId != null) {
        return hw.classroomId == child.classId;
      }
      return hw.classroomName.toLowerCase().trim() == child.className.toLowerCase().trim();
    }).toList();
  }

  List<AnnouncementModel> _filterNoticesByChild(List<AnnouncementModel> list, StudentModel? child) {
    if (child == null) return list;
    return list.where((notice) {
      if (!notice.isClassTargeted) return true;
      if (child.classId != null && notice.targetClassId != null) {
        return notice.targetClassId == child.classId;
      }
      return true;
    }).toList();
  }
}
