/// How a student was marked on one day.
enum AttendanceStatus {
  present('PRESENT', 'Present'),
  absent('ABSENT', 'Absent'),
  late('LATE', 'Late'),
  excused('EXCUSED', 'Excused');

  const AttendanceStatus(this.code, this.label);

  final String code;
  final String label;

  /// Late still counts as attending — the child was in class.
  bool get countsAsAttended =>
      this == AttendanceStatus.present || this == AttendanceStatus.late;

  static AttendanceStatus? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final value in AttendanceStatus.values) {
      if (value.code == code.toUpperCase()) return value;
    }
    return null;
  }
}

/// One row of a class register: a student and how they are marked today.
/// [status] is null until somebody marks the day.
class AttendanceEntry {
  const AttendanceEntry({
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    this.status,
    this.note = '',
  });

  final int studentId;
  final String studentName;
  final String admissionNumber;
  final AttendanceStatus? status;
  final String note;

  AttendanceEntry copyWith({AttendanceStatus? status, String? note}) {
    return AttendanceEntry(
      studentId: studentId,
      studentName: studentName,
      admissionNumber: admissionNumber,
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }

  factory AttendanceEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceEntry(
      studentId: json['student'] is int
          ? json['student'] as int
          : int.tryParse('${json['student']}') ?? 0,
      studentName: (json['student_name'] ?? '').toString(),
      admissionNumber: (json['admission_number'] ?? '').toString(),
      status: AttendanceStatus.fromCode(json['status']?.toString()),
      note: (json['note'] ?? '').toString(),
    );
  }
}

/// A class register for one date.
class AttendanceSheet {
  const AttendanceSheet({
    required this.classId,
    required this.className,
    required this.date,
    required this.alreadyMarked,
    required this.entries,
  });

  final int classId;
  final String className;
  final String date;

  /// Whether this day has been marked before — the screen says "update"
  /// rather than "save" when it has.
  final bool alreadyMarked;
  final List<AttendanceEntry> entries;

  AttendanceSheet copyWith({List<AttendanceEntry>? entries}) {
    return AttendanceSheet(
      classId: classId,
      className: className,
      date: date,
      alreadyMarked: alreadyMarked,
      entries: entries ?? this.entries,
    );
  }

  int countOf(AttendanceStatus status) =>
      entries.where((entry) => entry.status == status).length;

  int get unmarkedCount => entries.where((entry) => entry.status == null).length;

  factory AttendanceSheet.fromJson(Map<String, dynamic> json) {
    return AttendanceSheet(
      classId: json['classroom'] is int
          ? json['classroom'] as int
          : int.tryParse('${json['classroom']}') ?? 0,
      className: (json['classroom_name'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      alreadyMarked: json['already_marked'] == true,
      entries: (json['students'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AttendanceEntry.fromJson)
          .toList(),
    );
  }
}

/// A single child's attendance record, as a parent sees it.
class AttendanceSummary {
  const AttendanceSummary({
    required this.studentId,
    required this.daysRecorded,
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
    this.percentage,
    this.recent = const [],
  });

  final int studentId;
  final int daysRecorded;
  final int present;
  final int absent;
  final int late;
  final int excused;

  /// Null when no day has been recorded yet — that is different from 0%.
  final double? percentage;
  final List<AttendanceDay> recent;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    int asInt(String key) =>
        json[key] is int ? json[key] as int : int.tryParse('${json[key]}') ?? 0;

    final rawPercentage = json['attendance_percentage'];
    return AttendanceSummary(
      studentId: asInt('student_id'),
      daysRecorded: asInt('days_recorded'),
      present: asInt('present'),
      absent: asInt('absent'),
      late: asInt('late'),
      excused: asInt('excused'),
      percentage: rawPercentage == null
          ? null
          : double.tryParse(rawPercentage.toString()),
      recent: (json['recent'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AttendanceDay.fromJson)
          .toList(),
    );
  }
}

/// One recorded day in a student's history.
class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.status,
    this.note = '',
    this.className = '',
  });

  final DateTime date;
  final AttendanceStatus status;
  final String note;
  final String className;

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    return AttendanceDay(
      date: DateTime.tryParse((json['date'] ?? '').toString()) ?? DateTime.now(),
      status: AttendanceStatus.fromCode(json['status']?.toString()) ??
          AttendanceStatus.present,
      note: (json['note'] ?? '').toString(),
      className: (json['classroom_name'] ?? '').toString(),
    );
  }
}
