import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../classes/models/class_model.dart';
import '../../classes/providers/classes_provider.dart';
import '../models/attendance_model.dart';
import '../providers/attendance_provider.dart';

/// The register a teacher opens each morning.
///
/// Designed around the one thing that matters here: marking 40 children has to
/// take seconds. Everyone starts Present with one tap, and the teacher only
/// touches the few who are not.
class MarkAttendanceScreen extends ConsumerStatefulWidget {
  const MarkAttendanceScreen({super.key, this.initialClassId});

  final int? initialClassId;

  @override
  ConsumerState<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> {
  int? _classId;
  DateTime _date = DateTime.now();
  List<AttendanceEntry>? _draft;
  int? _draftForClass;
  String? _draftForDate;
  bool _saving = false;

  AttendanceQuery? get _query =>
      _classId == null ? null : AttendanceQuery(classId: _classId!, date: _date);

  /// Keeps the teacher's un-saved taps when the sheet reloads underneath.
  List<AttendanceEntry> _entriesFor(AttendanceSheet sheet) {
    if (_draft != null &&
        _draftForClass == sheet.classId &&
        _draftForDate == sheet.date) {
      return _draft!;
    }
    _draft = List<AttendanceEntry>.from(sheet.entries);
    _draftForClass = sheet.classId;
    _draftForDate = sheet.date;
    return _draft!;
  }

  void _setStatus(int studentId, AttendanceStatus status) {
    setState(() {
      _draft = [
        for (final entry in _draft ?? const <AttendanceEntry>[])
          entry.studentId == studentId ? entry.copyWith(status: status) : entry,
      ];
    });
  }

  void _markAllPresent() {
    setState(() {
      _draft = [
        for (final entry in _draft ?? const <AttendanceEntry>[])
          entry.copyWith(status: AttendanceStatus.present),
      ];
    });
  }

  Future<void> _save(AttendanceSheet sheet) async {
    final entries = _entriesFor(sheet);
    setState(() => _saving = true);

    final error = await ref.read(attendanceMarkerProvider).markClass(
          classId: sheet.classId,
          isoDate: sheet.date,
          entries: entries,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    final messenger = ScaffoldMessenger.of(context);
    if (error == null) {
      ref.invalidate(attendanceSheetProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Attendance saved for ${sheet.className}'),
          backgroundColor: AppColors.statusActiveText,
        ),
      );
      Navigator.of(context).maybePop();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.priorityUrgentText),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final classes = classesAsync.value ?? const <ClassModel>[];

    // Default to the class the caller asked for, else the teacher's first.
    if (_classId == null && classes.isNotEmpty) {
      _classId = classes.any((c) => c.id == widget.initialClassId)
          ? widget.initialClassId
          : classes.first.id;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Attendance',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: classes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No classes assigned to you yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : Column(
              children: [
                _pickerBar(classes),
                Expanded(child: _register()),
              ],
            ),
      bottomNavigationBar: classes.isEmpty ? null : _saveBar(),
    );
  }

  Widget _saveBar() {
    final query = _query;
    final sheet = query == null
        ? null
        : ref.watch(attendanceSheetProvider(query)).value;
    if (sheet == null) return const SizedBox.shrink();

    final entries = _draft ?? sheet.entries;
    final marked = entries.where((entry) => entry.status != null).length;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _saving || marked == 0 ? null : () => _save(sheet),
            icon: _saving
                ? const SizedBox(
                    height: 17,
                    width: 17,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 19),
            label: Text(
              _saving
                  ? 'Saving…'
                  : sheet.alreadyMarked
                      ? 'Update attendance ($marked)'
                      : 'Save attendance ($marked)',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              disabledForegroundColor: AppColors.textMuted,
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerBar(List<ClassModel> classes) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  items: classes
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.displayName, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _classId = value;
                      _draft = null;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 180)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() {
                    _date = picked;
                    _draft = null;
                  });
                }
              },
              borderRadius: BorderRadius.circular(11),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _isToday(_date) ? 'Today' : '${_date.day}/${_date.month}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Widget _register() {
    final query = _query;
    if (query == null) return const SizedBox.shrink();

    return ref.watch(attendanceSheetProvider(query)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Could not load the register.\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
          data: (sheet) {
            final entries = _entriesFor(sheet);
            if (entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No students in this class yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }

            return Column(
              children: [
                _tallyBar(entries, sheet),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _studentRow(entries[index]),
                  ),
                ),
              ],
            );
          },
        );
  }

  Widget _tallyBar(List<AttendanceEntry> entries, AttendanceSheet sheet) {
    int count(AttendanceStatus status) =>
        entries.where((entry) => entry.status == status).length;
    final unmarked = entries.where((entry) => entry.status == null).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _tally('${count(AttendanceStatus.present)}', 'present',
                    AppColors.statStudentsText, AppColors.statStudentsBg),
                _tally('${count(AttendanceStatus.absent)}', 'absent',
                    AppColors.priorityUrgentText, AppColors.priorityUrgentBg),
                if (count(AttendanceStatus.late) > 0)
                  _tally('${count(AttendanceStatus.late)}', 'late',
                      AppColors.statHomeworkText, AppColors.statHomeworkBg),
                if (unmarked > 0)
                  _tally('$unmarked', 'unmarked',
                      AppColors.textSecondary, AppColors.surfaceElevated),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _markAllPresent,
            icon: const Icon(Icons.done_all_rounded, size: 17),
            label: const Text('All present', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tally(String value, String label, Color color, Color background) {
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

  Widget _studentRow(AttendanceEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.admissionNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusButton(entry, AttendanceStatus.present, 'P',
              AppColors.statStudentsText, AppColors.statStudentsBg),
          const SizedBox(width: 6),
          _statusButton(entry, AttendanceStatus.absent, 'A',
              AppColors.priorityUrgentText, AppColors.priorityUrgentBg),
          const SizedBox(width: 6),
          _statusButton(entry, AttendanceStatus.late, 'L',
              AppColors.statHomeworkText, AppColors.statHomeworkBg),
        ],
      ),
    );
  }

  Widget _statusButton(
    AttendanceEntry entry,
    AttendanceStatus status,
    String letter,
    Color color,
    Color background,
  ) {
    final selected = entry.status == status;
    return Semantics(
      label: '${status.label} for ${entry.studentName}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => _setStatus(entry.studentId, status),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : background,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? color : Colors.transparent,
            ),
          ),
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}
