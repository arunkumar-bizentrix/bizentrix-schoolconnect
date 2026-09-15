import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../exams/models/exam_models.dart';
import '../../exams/screens/report_card_screen.dart';
import '../../timetable/screens/timetable_screen.dart';
import '../models/child_today.dart';

/// One child's day on a single card: attendance, the period running now,
/// homework that came home, and the last exam.
class ChildTodayCard extends StatelessWidget {
  const ChildTodayCard({super.key, required this.today, this.now});

  final ChildToday today;

  /// Injected by tests; the live clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AttendanceBand(today: today),
          if (today.periods.isNotEmpty) _Periods(today: today, now: clock),
          _Homework(today: today),
          if (today.latestResult != null) _Result(today: today),
          _Links(today: today),
        ],
      ),
    );
  }
}

class _AttendanceBand extends StatelessWidget {
  const _AttendanceBand({required this.today});

  final ChildToday today;

  @override
  Widget build(BuildContext context) {
    final attendance = today.attendance;
    final (Color background, Color foreground, IconData icon, String headline) = switch (attendance.status) {
      'PRESENT' => (AppColors.statusActiveText, Colors.white, Icons.check_circle_rounded, 'reached school'),
      'LATE' => (AppColors.statHomeworkText, Colors.white, Icons.schedule_rounded, 'came in late'),
      'ABSENT' => (AppColors.statusOverdueText, Colors.white, Icons.cancel_rounded, 'is absent today'),
      'EXCUSED' => (AppColors.priorityImportantText, Colors.white, Icons.event_busy_rounded, 'is on leave today'),
      _ => (AppColors.surfaceElevated, AppColors.textPrimary, Icons.hourglass_empty_rounded, 'attendance not marked yet'),
    };
    final subtle = attendance.isMarked ? Colors.white70 : AppColors.textSecondary;

    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attendance.isMarked ? '${today.firstName} $headline' : '${today.firstName}: $headline',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: foreground, height: 1.2),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (today.classroomName != null) today.classroomName!,
                    if (attendance.note.isNotEmpty) attendance.note,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: subtle),
                ),
              ],
            ),
          ),
          if (attendance.percentage != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatMarks(attendance.percentage)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text('attendance', style: TextStyle(fontSize: 11, color: subtle)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Periods extends StatelessWidget {
  const _Periods({required this.today, required this.now});

  final ChildToday today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final running = today.periods.where((p) => p.isRunningAt(now)).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              running != null
                  ? 'Now: ${running.subjectName}${running.teacherName != null ? ' with ${running.teacherName}' : ''}'
                  : "Today's periods",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              itemCount: today.periods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final period = today.periods[index];
                final live = identical(period, running);
                return Container(
                  constraints: const BoxConstraints(minWidth: 72, maxWidth: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: live ? AppColors.primary : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: live ? AppColors.primary : AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'P${period.period}',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: live ? Colors.white70 : AppColors.textMuted),
                      ),
                      Text(
                        period.subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: live ? Colors.white : AppColors.textPrimary),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Homework extends StatelessWidget {
  const _Homework({required this.today});

  final ChildToday today;

  @override
  Widget build(BuildContext context) {
    final given = today.homeworkToday;
    final dueSoon = today.homeworkDueSoon;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            given.isEmpty ? 'No new homework today' : 'Homework given today · ${given.length}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          for (final item in given.take(3)) _HomeworkLine(item: item),
          if (given.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('+${given.length - 3} more in Homework', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          if (dueSoon.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Due in the next few days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            for (final item in dueSoon.take(3)) _HomeworkLine(item: item),
          ],
        ],
      ),
    );
  }
}

class _HomeworkLine extends StatelessWidget {
  const _HomeworkLine({required this.item});

  final TodayHomework item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: item.dueToday ? AppColors.statusOverdueText : AppColors.statHomeworkText,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${item.subject}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: item.title),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.dueToday ? 'Due today' : item.dueDisplay,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: item.dueToday ? FontWeight.w700 : FontWeight.w500,
              color: item.dueToday ? AppColors.statusOverdueText : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.today});

  final ChildToday today;

  @override
  Widget build(BuildContext context) {
    final result = today.latestResult!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: AppColors.statClassesBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReportCardScreen(studentId: today.studentId)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.examName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.statClassesText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatMarks(result.percentage)}% · ${formatMarks(result.total)}/${result.maxTotal}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (result.rank != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ordinal(result.rank!),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.statClassesText),
                      ),
                      Text('of ${result.classSize}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: AppColors.statClassesText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Links extends StatelessWidget {
  const _Links({required this.today});

  final ChildToday today;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          if (today.classroomId != null)
            Expanded(
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TimetableScreen(
                      classId: today.classroomId!,
                      title: '${today.firstName}’s timetable',
                    ),
                  ),
                ),
                icon: const Icon(Icons.calendar_view_week_outlined, size: 18),
                label: const Text('Timetable'),
              ),
            ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReportCardScreen(studentId: today.studentId)),
              ),
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('Report card'),
            ),
          ),
        ],
      ),
    );
  }
}
