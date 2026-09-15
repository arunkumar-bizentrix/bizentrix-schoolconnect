/// One period in the weekly schedule.
class TimetablePeriod {
  const TimetablePeriod({
    required this.id,
    required this.period,
    required this.subjectName,
    this.subjectCode = '',
    this.teacherName,
    this.className = '',
    this.timeDisplay = '',
    this.room = '',
  });

  final int id;
  final int period;
  final String subjectName;
  final String subjectCode;

  /// Null when no teacher has been assigned to the period yet.
  final String? teacherName;
  final String className;

  /// Server-formatted, e.g. "9:00 AM - 9:45 AM", or "Period 3" when the
  /// school has not set clock times.
  final String timeDisplay;
  final String room;

  factory TimetablePeriod.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

    return TimetablePeriod(
      id: asInt(json['id']),
      period: asInt(json['period']),
      subjectName: (json['subject_name'] ?? '').toString(),
      subjectCode: (json['subject_code'] ?? '').toString(),
      teacherName: json['teacher_name']?.toString(),
      className: (json['classroom_name'] ?? '').toString(),
      timeDisplay: (json['time_display'] ?? '').toString(),
      room: (json['room'] ?? '').toString(),
    );
  }
}

/// One weekday and the periods on it.
class TimetableDay {
  const TimetableDay({
    required this.weekday,
    required this.weekdayName,
    required this.periods,
  });

  /// 0 = Monday, matching Dart's DateTime.weekday - 1.
  final int weekday;
  final String weekdayName;
  final List<TimetablePeriod> periods;

  bool get isEmpty => periods.isEmpty;

  factory TimetableDay.fromJson(Map<String, dynamic> json) {
    return TimetableDay(
      weekday: json['weekday'] is int
          ? json['weekday'] as int
          : int.tryParse('${json['weekday']}') ?? 0,
      weekdayName: (json['weekday_name'] ?? '').toString(),
      periods: (json['periods'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TimetablePeriod.fromJson)
          .toList(),
    );
  }
}

/// A full week, either for one class or for one teacher.
class TimetableWeek {
  const TimetableWeek({
    required this.days,
    this.className = '',
    this.classId,
  });

  final List<TimetableDay> days;
  final String className;
  final int? classId;

  bool get isEmpty => days.every((day) => day.isEmpty);

  /// Today's row, or null on a day the school does not run.
  TimetableDay? get today {
    final todayIndex = DateTime.now().weekday - 1; // Dart: Monday == 1
    for (final day in days) {
      if (day.weekday == todayIndex) return day;
    }
    return null;
  }

  factory TimetableWeek.fromJson(Map<String, dynamic> json) {
    return TimetableWeek(
      classId: json['classroom'] is int ? json['classroom'] as int : null,
      className: (json['classroom_name'] ?? '').toString(),
      days: (json['days'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TimetableDay.fromJson)
          .toList(),
    );
  }
}
