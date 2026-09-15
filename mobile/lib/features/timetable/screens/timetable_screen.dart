import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/role_access.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/timetable_model.dart';
import '../providers/timetable_provider.dart';
import 'timetable_editor_screen.dart';

/// The weekly timetable.
///
/// Two audiences, one screen: a teacher opens their own week ([forTeacher]),
/// a parent opens their child's class week. Today's column is selected on
/// open, because "what is happening now" is the question people actually have.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key, this.classId, this.title});

  /// Null means "the signed-in teacher's own schedule".
  final int? classId;
  final String? title;

  const TimetableScreen.forTeacher({super.key})
      : classId = null,
        title = 'My timetable';

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  int? _selectedWeekday;

  @override
  Widget build(BuildContext context) {
    final weekAsync = widget.classId == null
        ? ref.watch(myTimetableProvider)
        : ref.watch(classTimetableProvider(widget.classId!));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          widget.title ?? 'Timetable',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (ref.watch(authProvider).user?.role.isAdmin ?? false)
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, size: 21),
              tooltip: 'Edit timetable',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TimetableEditorScreen()),
              ),
            ),
        ],
      ),
      body: weekAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'Could not load the timetable.\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ),
        data: (week) => _week(week),
      ),
    );
  }

  Widget _week(TimetableWeek week) {
    if (week.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No timetable has been set up yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final todayIndex = DateTime.now().weekday - 1;
    final selected = _selectedWeekday ??
        (week.days.any((day) => day.weekday == todayIndex)
            ? todayIndex
            : week.days.first.weekday);

    final day = week.days.firstWhere(
      (candidate) => candidate.weekday == selected,
      orElse: () => week.days.first,
    );

    return Column(
      children: [
        if (week.className.isNotEmpty) _classBanner(week.className),
        _dayStrip(week, selected, todayIndex),
        Expanded(child: _periods(day, isToday: day.weekday == todayIndex)),
      ],
    );
  }

  Widget _classBanner(String className) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        className,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _dayStrip(TimetableWeek week, int selected, int todayIndex) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: week.days.map((day) {
            final isSelected = day.weekday == selected;
            final isToday = day.weekday == todayIndex;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedWeekday = day.weekday),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // Three letters keeps six days on one strip.
                        day.weekdayName.length > 3
                            ? day.weekdayName.substring(0, 3)
                            : day.weekdayName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isSelected ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _periods(TimetableDay day, {required bool isToday}) {
    if (day.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No periods on ${day.weekdayName}.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: day.periods.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _periodCard(day.periods[index], isToday),
    );
  }

  Widget _periodCard(TimetablePeriod period, bool isToday) {
    // Rotating the accent by subject makes a day scannable at a glance.
    const accents = [
      [AppColors.statClassesText, AppColors.statClassesBg],
      [AppColors.statStudentsText, AppColors.statStudentsBg],
      [AppColors.statHomeworkText, AppColors.statHomeworkBg],
      [AppColors.priorityImportantText, AppColors.priorityImportantBg],
      [AppColors.statAnnouncementsText, AppColors.statAnnouncementsBg],
    ];
    final accent = accents[period.subjectName.hashCode.abs() % accents.length];

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent[1],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'P${period.period}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: accent[0],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  period.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (period.timeDisplay.isNotEmpty) period.timeDisplay,
                    if (period.className.isNotEmpty) period.className,
                    if (period.teacherName != null &&
                        period.teacherName!.isNotEmpty)
                      period.teacherName!,
                    if (period.room.isNotEmpty) 'Room ${period.room}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
