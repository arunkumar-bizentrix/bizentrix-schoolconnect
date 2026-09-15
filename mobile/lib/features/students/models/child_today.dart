import '../../exams/models/exam_models.dart';

/// Everything a parent checks each day about one child, from
/// GET /api/v1/parent/today/.
class ChildToday {
  const ChildToday({
    required this.studentId,
    required this.studentName,
    this.classroomId,
    this.classroomName,
    this.classTeacherName,
    required this.attendance,
    required this.periods,
    required this.homeworkToday,
    required this.homeworkDueSoon,
    this.latestResult,
  });

  final int studentId;
  final String studentName;
  final int? classroomId;
  final String? classroomName;
  final String? classTeacherName;
  final TodayAttendance attendance;
  final List<TodayPeriod> periods;
  final List<TodayHomework> homeworkToday;
  final List<TodayHomework> homeworkDueSoon;
  final LatestResult? latestResult;

  String get firstName => studentName.split(' ').first;

  factory ChildToday.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (json[key] as List? ?? const []).whereType<Map<String, dynamic>>().map(parse).toList();

    return ChildToday(
      studentId: json['student'] as int? ?? 0,
      studentName: '${json['student_name'] ?? ''}',
      classroomId: json['classroom'] as int?,
      classroomName: json['classroom_name']?.toString(),
      classTeacherName: json['class_teacher_name']?.toString(),
      attendance: TodayAttendance.fromJson(Map<String, dynamic>.from(json['attendance'] as Map? ?? const {})),
      periods: list('periods', TodayPeriod.fromJson),
      homeworkToday: list('homework_today', TodayHomework.fromJson),
      homeworkDueSoon: list('homework_due_soon', TodayHomework.fromJson),
      latestResult: json['latest_result'] is Map
          ? LatestResult.fromJson(Map<String, dynamic>.from(json['latest_result'] as Map))
          : null,
    );
  }
}

class TodayAttendance {
  const TodayAttendance({this.status, this.note = '', this.percentage, this.daysRecorded = 0});

  /// PRESENT, ABSENT, LATE, EXCUSED, or null when not marked yet.
  final String? status;
  final String note;
  final double? percentage;
  final int daysRecorded;

  bool get isMarked => status != null;

  factory TodayAttendance.fromJson(Map<String, dynamic> json) {
    return TodayAttendance(
      status: json['status']?.toString(),
      note: '${json['note'] ?? ''}',
      percentage: (json['percentage'] as num?)?.toDouble(),
      daysRecorded: (json['days_recorded'] as num?)?.toInt() ?? 0,
    );
  }
}

class TodayPeriod {
  const TodayPeriod({
    required this.period,
    required this.subjectName,
    this.teacherName,
    this.startTime,
    this.endTime,
    this.timeDisplay = '',
  });

  final int period;
  final String subjectName;
  final String? teacherName;

  /// "HH:MM:SS" from the API, or null when the school has not set times.
  final String? startTime;
  final String? endTime;
  final String timeDisplay;

  static int? _minutes(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    return hours * 60 + minutes;
  }

  /// Whether this period is running at [now].
  bool isRunningAt(DateTime now) {
    final start = _minutes(startTime);
    final end = _minutes(endTime);
    if (start == null || end == null) return false;
    final current = now.hour * 60 + now.minute;
    return current >= start && current < end;
  }

  factory TodayPeriod.fromJson(Map<String, dynamic> json) {
    return TodayPeriod(
      period: (json['period'] as num?)?.toInt() ?? 0,
      subjectName: '${json['subject_name'] ?? ''}',
      teacherName: json['teacher_name']?.toString(),
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
      timeDisplay: '${json['time_display'] ?? ''}',
    );
  }
}

class TodayHomework {
  const TodayHomework({
    required this.id,
    required this.title,
    required this.subject,
    required this.dueDisplay,
    this.dueToday = false,
  });

  final int id;
  final String title;
  final String subject;
  final String dueDisplay;
  final bool dueToday;

  factory TodayHomework.fromJson(Map<String, dynamic> json) {
    return TodayHomework(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: '${json['title'] ?? ''}',
      subject: '${json['subject'] ?? ''}',
      dueDisplay: '${json['due_display'] ?? json['due_date'] ?? ''}',
      dueToday: json['due_today'] == true,
    );
  }
}

class LatestResult {
  const LatestResult({
    required this.examName,
    required this.total,
    required this.maxTotal,
    required this.percentage,
    required this.outcome,
    required this.classSize,
    this.rank,
  });

  final String examName;
  final double total;
  final int maxTotal;
  final double percentage;
  final ExamOutcome outcome;
  final int classSize;
  final int? rank;

  factory LatestResult.fromJson(Map<String, dynamic> json) {
    return LatestResult(
      examName: '${json['exam_name'] ?? ''}',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      maxTotal: (json['max_total'] as num?)?.toInt() ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
      outcome: ExamOutcome.parse(json['result']),
      classSize: (json['class_size'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt(),
    );
  }
}
