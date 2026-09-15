import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/role_access.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../attendance/screens/mark_attendance_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../exams/models/exam_models.dart';
import '../../exams/screens/exam_detail_screen.dart';
import '../../exams/screens/exams_screen.dart';
import '../../timetable/screens/timetable_screen.dart';
import '../providers/monitoring_provider.dart';
import '../widgets/section.dart';
import 'student_profile_screen.dart';

/// One class for staff: teachers and subjects, today's attendance, each
/// student's attendance percentage, recent homework and its exams.
class ClassOverviewScreen extends ConsumerWidget {
  const ClassOverviewScreen({super.key, required this.classId, this.title});

  final int classId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(classOverviewProvider(classId));
    final isTeacher = ref.watch(authProvider).user?.role.isTeacher ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(overviewAsync.value?.name ?? title ?? 'Class',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Timetable',
            icon: const Icon(Icons.calendar_view_week_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => TimetableScreen(classId: classId, title: overviewAsync.value?.name ?? title))),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(classOverviewProvider(classId)),
        child: overviewAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [ErrorStateView(message: friendlyError(ref, error))]),
          data: (c) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Section(
                title: 'Today',
                trailing: isTeacher
                    ? TextButton(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => MarkAttendanceScreen(initialClassId: classId))),
                        child: const Text('Mark attendance'),
                      )
                    : null,
                child: c.attendanceMarkedToday
                    ? Wrap(spacing: 8, runSpacing: 8, children: [
                        Figure(value: '${c.presentToday}', label: 'Present', color: AppColors.statusActiveText),
                        Figure(value: '${c.absentToday}', label: 'Absent', color: AppColors.statusOverdueText),
                        if (c.notMarkedToday > 0) Figure(value: '${c.notMarkedToday}', label: 'Not marked'),
                      ])
                    : const Text('Attendance has not been taken today.',
                        style: TextStyle(color: AppColors.statHomeworkText, fontWeight: FontWeight.w600)),
              ),
              Section(
                title: 'Teachers',
                child: Column(children: [
                  KeyValue('Class teacher', c.classTeacherName ?? 'Not assigned'),
                  for (final t in c.teachers.where((t) => !t.isClassTeacher)) KeyValue('Teacher', t.name),
                ]),
              ),
              Section(
                title: 'Subjects',
                child: c.subjects.isEmpty
                    ? const Text('No timetable yet, so no subjects are scheduled.',
                        style: TextStyle(color: AppColors.textSecondary))
                    : Column(children: [
                        for (final s in c.subjects)
                          KeyValue(s.subject,
                              '${s.teachers.isEmpty ? 'No teacher' : s.teachers.join(', ')} · ${s.periods} a week'),
                      ]),
              ),
              Section(
                title: 'Students (${c.studentCount})',
                child: c.students.isEmpty
                    ? const Text('No students in this class.', style: TextStyle(color: AppColors.textSecondary))
                    : Column(children: [
                        for (final s in c.students)
                          InkWell(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => StudentProfileScreen(studentId: s.id))),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                        Text(
                                          '${s.admission}${s.parents == 0 ? ' · no parent linked' : ''}',
                                          style: TextStyle(fontSize: 11.5,
                                              color: s.parents == 0 ? AppColors.statHomeworkText : AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    s.attendance == null ? '-' : '${formatMarks(s.attendance)}%',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: (s.attendance ?? 100) < 75 ? AppColors.statusOverdueText : AppColors.textPrimary,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                      ]),
              ),
              Section(
                title: 'Homework',
                trailing: Text('${c.activeHomework} active',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                child: c.recentHomework.isEmpty
                    ? const Text('No homework yet.', style: TextStyle(color: AppColors.textSecondary))
                    : Column(children: [
                        for (final h in c.recentHomework)
                          KeyValue(h.subject, '${h.title} · due ${h.due}${h.by.isEmpty ? '' : ' · ${h.by}'}'),
                      ]),
              ),
              if (c.exams.isNotEmpty)
                Section(
                  title: 'Exams',
                  child: Column(children: [
                    for (final exam in c.exams)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(exam.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: PublishStateChip(isPublished: exam.published),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ExamDetailScreen(examId: exam.id, title: exam.name))),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
