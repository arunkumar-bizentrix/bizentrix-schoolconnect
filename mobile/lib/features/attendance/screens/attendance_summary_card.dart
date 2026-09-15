import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../models/attendance_model.dart';
import '../providers/attendance_provider.dart';

/// A child's attendance at a glance, for the parent dashboard.
///
/// Shows the percentage prominently because that is the number a parent
/// actually tracks, then the recent days so an absence has context.
class AttendanceSummaryCard extends ConsumerWidget {
  const AttendanceSummaryCard({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  final int studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(attendanceSummaryProvider(studentId)).when(
          loading: () => const _Shell(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (summary) {
            if (summary.daysRecorded == 0) {
              return const _Shell(
                child: Text(
                  'Attendance has not been recorded yet.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              );
            }
            return _Shell(child: _body(summary));
          },
        );
  }

  Widget _body(AttendanceSummary summary) {
    final percentage = summary.percentage ?? 0;
    // Below 75% is the line most schools act on, so it reads as a warning.
    final good = percentage >= 75;
    final accent = good ? AppColors.statStudentsText : AppColors.priorityUrgentText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attendance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$studentName · ${summary.daysRecorded} days recorded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${percentage.toStringAsFixed(percentage % 1 == 0 ? 0 : 1)}%',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: (percentage / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _chip('${summary.present}', 'present', AppColors.statStudentsText,
                AppColors.statStudentsBg),
            if (summary.late > 0)
              _chip('${summary.late}', 'late', AppColors.statHomeworkText,
                  AppColors.statHomeworkBg),
            if (summary.absent > 0)
              _chip('${summary.absent}', 'absent', AppColors.priorityUrgentText,
                  AppColors.priorityUrgentBg),
            if (summary.excused > 0)
              _chip('${summary.excused}', 'excused', AppColors.textSecondary,
                  AppColors.surfaceElevated),
          ],
        ),
        if (summary.recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Recent days',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: summary.recent.take(12).map(_dayPill).toList(),
          ),
        ],
      ],
    );
  }

  Widget _chip(String value, String label, Color color, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _dayPill(AttendanceDay day) {
    final attended = day.status.countsAsAttended;
    final color = day.status == AttendanceStatus.absent
        ? AppColors.priorityUrgentText
        : day.status == AttendanceStatus.late
            ? AppColors.statHomeworkText
            : attended
                ? AppColors.statStudentsText
                : AppColors.textSecondary;

    return Tooltip(
      message: '${day.date.day}/${day.date.month} · ${day.status.label}'
          '${day.note.isNotEmpty ? ' · ${day.note}' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${day.date.day}/${day.date.month}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
