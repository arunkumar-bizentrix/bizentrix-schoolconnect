import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../exams/screens/exams_screen.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/screens/chat_screen.dart';
import '../providers/monitoring_provider.dart';
import '../widgets/section.dart';
import 'class_overview_screen.dart';

/// One teacher, for the admin: classes, subjects, week, and last 30 days.
class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({super.key, required this.teacherId});

  final int teacherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(teacherProfileProvider(teacherId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(profileAsync.value?.fullName ?? 'Teacher',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
        actions: [
          if (profileAsync.value != null)
            IconButton(
              tooltip: 'Message',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen.newConversation(
                    recipient: MessageContact(id: profileAsync.value!.id, fullName: profileAsync.value!.fullName,
                        role: 'TEACHER', context: 'Teacher'),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(teacherProfileProvider(teacherId)),
        child: profileAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [ErrorStateView(message: friendlyError(ref, error))]),
          data: (t) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Section(
                title: 'Contact',
                child: Column(children: [
                  KeyValue('Mobile', t.phone.isEmpty ? '-' : t.phone),
                  KeyValue('Email', t.email.isEmpty ? '-' : t.email),
                  KeyValue('Status', t.isActive ? 'Active' : 'Deactivated'),
                ]),
              ),
              Section(
                title: 'Last 30 days',
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  Figure(value: '${t.homeworkSet}', label: 'Homework set'),
                  Figure(value: '${t.attendanceDaysMarked}', label: 'Attendance days'),
                  Figure(value: '${t.marksEntered}', label: 'Marks entered'),
                  Figure(value: '${t.announcementsPosted}', label: 'Notices'),
                ]),
              ),
              Section(
                title: 'Classes',
                child: t.classes.isEmpty
                    ? const Text('Not assigned to a class yet.', style: TextStyle(color: AppColors.statHomeworkText))
                    : Column(children: [
                        for (final c in t.classes)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${c.students} students${c.isClassTeacher ? ' · class teacher' : ''}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ClassOverviewScreen(classId: c.id, title: c.name))),
                          ),
                      ]),
              ),
              Section(
                title: 'Subjects',
                child: t.subjects.isEmpty
                    ? const Text('No periods in the timetable yet.', style: TextStyle(color: AppColors.textSecondary))
                    : Column(children: [
                        for (final s in t.subjects) KeyValue(s.subject, '${s.classes.join(', ')} · ${s.periods} a week'),
                      ]),
              ),
              if (!t.timetable.isEmpty)
                Section(
                  title: 'Week',
                  child: Column(children: [
                    for (final day in t.timetable.days.where((d) => d.periods.isNotEmpty))
                      KeyValue(
                        day.weekdayName,
                        day.periods.map((p) => 'P${p.period} ${p.subjectName} (${p.className})').join(' · '),
                      ),
                  ]),
                ),
              if (t.recentHomework.isNotEmpty)
                Section(
                  title: 'Recent homework',
                  child: Column(children: [
                    for (final h in t.recentHomework) KeyValue(h.className, '${h.subject}: ${h.title}'),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
