import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../auth/providers/auth_provider.dart';
import '../../exams/models/exam_models.dart';
import '../../exams/screens/exams_screen.dart';
import '../../exams/screens/report_card_screen.dart';
import '../../exams/widgets/grade_badge.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/screens/chat_screen.dart';
import '../models/monitoring_models.dart';
import '../providers/monitoring_provider.dart';
import '../widgets/section.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime? d) => d == null ? '-' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Everything about one student on one screen. Admin and the student's
/// teachers see it all; a parent sees their own child, results once published.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(studentProfileProvider(studentId));
    final role = ref.watch(authProvider).user?.role;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(profileAsync.value?.fullName ?? 'Student',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(studentProfileProvider(studentId)),
        child: profileAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [ErrorStateView(message: friendlyError(ref, error))]),
          data: (profile) => _body(context, profile, role),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StudentProfile p, UserRole? role) {
    final isParent = role == UserRole.parent;
    final isStaff = !isParent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Section(
          title: 'Student',
          child: Column(children: [
            KeyValue('Admission no.', p.admissionNumber),
            KeyValue('Class', p.className ?? 'Not in a class'),
            if (p.academicYear != null) KeyValue('Academic year', p.academicYear!),
            KeyValue('Class teacher', p.classTeacherName ?? 'Not assigned'),
            if (p.dateOfBirth != null) KeyValue('Date of birth', _day(p.dateOfBirth)),
          ]),
        ),
        if (isParent && p.classTeacherId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen.newConversation(
                    recipient: MessageContact(id: p.classTeacherId!, fullName: p.classTeacherName ?? 'Class teacher',
                        role: 'TEACHER', context: 'Class teacher, ${p.className ?? ''}'),
                  ),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Message the class teacher'),
            ),
          ),
        if (isStaff)
          Section(
            title: 'Parents',
            child: p.parents.isEmpty
                ? const Text('No parent linked yet.', style: TextStyle(color: AppColors.textSecondary))
                : Column(children: [
                    for (final parent in p.parents)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.family_restroom_outlined),
                        title: Text(parent.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([parent.phone, parent.email].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: IconButton(
                          tooltip: 'Message ${parent.name}',
                          icon: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen.newConversation(
                                recipient: MessageContact(id: parent.id, fullName: parent.name, role: 'PARENT',
                                    context: 'Parent of ${p.fullName}'),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
          ),
        Section(
          title: 'Attendance',
          trailing: Text(p.attendancePercentage == null ? 'Not recorded' : '${formatMarks(p.attendancePercentage)}%',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                Figure(value: '${p.daysPresent}', label: 'Present', color: AppColors.statusActiveText),
                Figure(value: '${p.daysLate}', label: 'Late', color: AppColors.statHomeworkText),
                Figure(value: '${p.daysAbsent}', label: 'Absent', color: AppColors.statusOverdueText),
                Figure(value: '${p.daysRecorded}', label: 'Days recorded'),
              ]),
              if (p.recentAttendance.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Recent days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final day in p.recentAttendance.take(20))
                      Tooltip(
                        message: '${_day(day.date)}: ${day.status.toLowerCase()}${day.note.isEmpty ? '' : ' - ${day.note}'}',
                        child: Container(
                          width: 34,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: (attendanceColors[day.status] ?? AppColors.textMuted).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${day.date?.day ?? ''}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                                  color: attendanceColors[day.status] ?? AppColors.textMuted)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Section(
          title: 'Results',
          trailing: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportCardScreen(studentId: p.id))),
            child: const Text('Report card'),
          ),
          child: p.results.isEmpty
              ? Text(isParent ? 'No published results yet.' : 'No exam results yet.',
                  style: const TextStyle(color: AppColors.textSecondary))
              : Column(children: [
                  for (final result in p.results)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(result.examName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                Text(
                                  [
                                    '${formatMarks(result.total)}/${result.maxTotal}',
                                    if (result.rank != null) 'Rank ${result.rank} of ${result.classSize}',
                                    if (!result.isPublished) 'Draft',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Text('${formatMarks(result.percentage)}%',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          GradeBadge(grade: result.grade),
                        ],
                      ),
                    ),
                ]),
        ),
        Section(
          title: 'Homework',
          trailing: Text('${p.activeHomework} due', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          child: p.recentHomework.isEmpty
              ? const Text('No homework yet.', style: TextStyle(color: AppColors.textSecondary))
              : Column(children: [
                  for (final h in p.recentHomework)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '${h.subject}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                TextSpan(text: h.title),
                                if (h.onlyThisChild) const TextSpan(text: '  (only this student)',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                              ]),
                              style: const TextStyle(fontSize: 13, height: 1.3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(h.due, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                ]),
        ),
        if (p.classHistory.length > 1)
          Section(
            title: 'Class history',
            child: Column(children: [
              for (final entry in p.classHistory)
                KeyValue(entry.year, '${entry.className}${entry.current ? ' (current)' : ''}'),
            ]),
          ),
      ],
    );
  }
}
