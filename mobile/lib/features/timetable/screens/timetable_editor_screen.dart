import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/models/staff_model.dart';
import '../../auth/providers/staff_provider.dart';
import '../../classes/models/class_model.dart';
import '../../classes/providers/class_options_provider.dart';
import '../models/subject_model.dart';
import '../models/timetable_model.dart';
import '../providers/timetable_editor_provider.dart';
import '../providers/timetable_provider.dart';

/// Admin-only timetable builder.
///
/// A school sets the timetable once a year and then patches it, so the screen
/// is built around one day at a time: pick a class, pick a day, add periods in
/// order. Conflicts are caught by the server and shown in full, because
/// "Priya already teaches 6-B in period 1" is the whole answer.
class TimetableEditorScreen extends ConsumerStatefulWidget {
  const TimetableEditorScreen({super.key});

  @override
  ConsumerState<TimetableEditorScreen> createState() => _TimetableEditorScreenState();
}

class _TimetableEditorScreenState extends ConsumerState<TimetableEditorScreen> {
  int? _classId;
  int _weekday = 0;

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().weekday - 1;
    _weekday = today >= 0 && today < _weekdayNames.length ? today : 0;
  }

  @override
  Widget build(BuildContext context) {
    final classes = ref.watch(currentClassOptionsProvider).value ?? const <ClassModel>[];
    if (_classId == null && classes.isNotEmpty) _classId = classes.first.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Edit timetable',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      floatingActionButton: _classId == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _showPeriodDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add period'),
            ),
      body: classes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Create a class first, then build its timetable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : Column(
              children: [
                _pickers(classes),
                Expanded(child: _dayList()),
              ],
            ),
    );
  }

  Widget _pickers(List<ClassModel> classes) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _classId,
                isExpanded: true,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                items: classes
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.displayName, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _classId = value),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_weekdayNames.length, (index) {
                final selected = index == _weekday;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _weekday = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.primary : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _weekdayNames[index].substring(0, 3),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayList() {
    final classId = _classId;
    if (classId == null) return const SizedBox.shrink();

    return ref.watch(classTimetableProvider(classId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
          data: (week) {
            final day = week.days.firstWhere(
              (candidate) => candidate.weekday == _weekday,
              orElse: () => TimetableDay(
                weekday: _weekday,
                weekdayName: _weekdayNames[_weekday],
                periods: const [],
              ),
            );

            if (day.periods.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_outlined,
                          size: 40, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No periods on ${_weekdayNames[_weekday]} yet.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap "Add period" to start.',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: day.periods.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) => _periodTile(day.periods[index]),
            );
          },
        );
  }

  Widget _periodTile(TimetablePeriod period) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.statClassesBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'P${period.period}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.statClassesText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  period.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (period.timeDisplay.isNotEmpty) period.timeDisplay,
                    period.teacherName ?? 'No teacher assigned',
                    if (period.room.isNotEmpty) 'Room ${period.room}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppColors.primary,
            tooltip: 'Edit period',
            onPressed: () => _showPeriodDialog(existing: period),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppColors.priorityUrgentText,
            tooltip: 'Remove period',
            onPressed: () => _confirmDelete(period),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(TimetablePeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove period?'),
        content: Text(
          'Period ${period.period} (${period.subjectName}) will be removed from '
          '${_weekdayNames[_weekday]}.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.priorityUrgentText)),
          ),
        ],
      ),
    );
    if (confirmed != true || _classId == null) return;

    final error = await ref.read(timetableEditorProvider).deletePeriod(
          slotId: period.id,
          classId: _classId!,
        );
    if (!mounted) return;
    _toast(error ?? 'Period removed', isError: error != null);
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? AppColors.priorityUrgentText : AppColors.statusActiveText,
      ),
    );
  }

  // ------------------------------------------------------------------
  // add / edit
  // ------------------------------------------------------------------

  Future<void> _showPeriodDialog({TimetablePeriod? existing}) async {
    final classId = _classId;
    if (classId == null) return;

    final isEdit = existing != null;
    final periodController =
        TextEditingController(text: '${existing?.period ?? _nextPeriodNumber()}');
    final roomController = TextEditingController(text: existing?.room ?? '');
    int? subjectId;
    int? teacherId;
    TimeOfDay? start;
    TimeOfDay? end;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final subjects =
              ref.watch(subjectsProvider).value ?? const <SubjectModel>[];
          final teachers = ref.watch(teachersProvider).value ?? const <StaffModel>[];

          // Pre-select what the period already has, matched by name because
          // the week payload carries names rather than ids.
          if (isEdit && subjectId == null && subjects.isNotEmpty) {
            subjectId = subjects
                .firstWhere(
                  (s) => s.name == existing.subjectName,
                  orElse: () => subjects.first,
                )
                .id;
          }
          if (isEdit && teacherId == null && existing.teacherName != null) {
            for (final teacher in teachers) {
              if (teacher.fullName == existing.teacherName) {
                teacherId = teacher.id;
                break;
              }
            }
          }

          return AlertDialog(
            title: Text(isEdit ? 'Edit period' : 'Add period'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_weekdayNames[_weekday]} · '
                    '${(ref.read(currentClassOptionsProvider).value ?? []).firstWhere((c) => c.id == classId, orElse: () => (ref.read(currentClassOptionsProvider).value ?? []).first).displayName}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: periodController,
                    enabled: !isEdit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Period number *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: subjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Subject *',
                      border: OutlineInputBorder(),
                    ),
                    items: subjects
                        .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) => setDialogState(() => subjectId = value),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addSubjectInline(setDialogState),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New subject',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: teacherId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Teacher',
                      border: OutlineInputBorder(),
                    ),
                    items: teachers
                        .map((t) => DropdownMenuItem(
                            value: t.id,
                            child:
                                Text(t.fullName, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) => setDialogState(() => teacherId = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _timeField(
                          label: 'Start',
                          value: start,
                          onPick: (picked) => setDialogState(() => start = picked),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _timeField(
                          label: 'End',
                          value: end,
                          onPick: (picked) => setDialogState(() => end = picked),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roomController,
                    decoration: const InputDecoration(
                      labelText: 'Room (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final periodNumber =
                            int.tryParse(periodController.text.trim());
                        if (periodNumber == null || periodNumber < 1) {
                          _toast('Enter a period number.', isError: true);
                          return;
                        }
                        if (subjectId == null) {
                          _toast('Pick a subject.', isError: true);
                          return;
                        }

                        setDialogState(() => saving = true);
                        final editor = ref.read(timetableEditorProvider);
                        final error = isEdit
                            ? await editor.updatePeriod(
                                slotId: existing.id,
                                classId: classId,
                                subjectId: subjectId!,
                                teacherId: teacherId,
                                startTime: _asApiTime(start),
                                endTime: _asApiTime(end),
                                room: roomController.text.trim(),
                              )
                            : await editor.addPeriod(
                                classId: classId,
                                weekday: _weekday,
                                period: periodNumber,
                                subjectId: subjectId!,
                                teacherId: teacherId,
                                startTime: _asApiTime(start),
                                endTime: _asApiTime(end),
                                room: roomController.text.trim(),
                              );
                        if (!dialogCtx.mounted) return;
                        setDialogState(() => saving = false);

                        if (error == null) {
                          Navigator.pop(dialogCtx);
                          if (!mounted) return;
                          _toast(isEdit ? 'Period updated' : 'Period added');
                        } else {
                          _toast(error, isError: true);
                        }
                      },
                child: Text(isEdit ? 'Save' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _timeField({
    required String label,
    required TimeOfDay? value,
    required ValueChanged<TimeOfDay> onPick,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 9, minute: 0),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          value == null ? '--:--' : value.format(context),
          style: TextStyle(
            fontSize: 13.5,
            color: value == null ? AppColors.textMuted : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  String? _asApiTime(TimeOfDay? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  int _nextPeriodNumber() {
    final week = _classId == null
        ? null
        : ref.read(classTimetableProvider(_classId!)).value;
    if (week == null) return 1;
    for (final day in week.days) {
      if (day.weekday == _weekday && day.periods.isNotEmpty) {
        return day.periods.map((p) => p.period).reduce((a, b) => a > b ? a : b) + 1;
      }
    }
    return 1;
  }

  Future<void> _addSubjectInline(void Function(void Function()) setDialogState) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New subject'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Subject name',
            hintText: 'e.g. Tamil',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    final error = await ref.read(timetableEditorProvider).addSubject(name);
    if (!mounted) return;
    if (error == null) {
      setDialogState(() {});
      _toast('"$name" added');
    } else {
      _toast(error, isError: true);
    }
  }
}
