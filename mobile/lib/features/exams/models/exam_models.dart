int _int(dynamic value, [int fallback = 0]) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? fallback;

int? _intOrNull(dynamic value) => value == null ? null : (value is int ? value : int.tryParse('$value'));

double? _doubleOrNull(dynamic value) =>
    value == null ? null : (value is num ? value.toDouble() : double.tryParse('$value'));

DateTime? _date(dynamic value) => value == null ? null : DateTime.tryParse('$value');

/// Marks like 88.0 read as "88"; 65.5 stays "65.5".
String formatMarks(num? value) {
  if (value == null) return '-';
  return value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
}

String ordinal(int rank) {
  final lastTwo = rank % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${rank}th';
  switch (rank % 10) {
    case 1:
      return '${rank}st';
    case 2:
      return '${rank}nd';
    case 3:
      return '${rank}rd';
    default:
      return '${rank}th';
  }
}

class ClassRef {
  const ClassRef({required this.id, required this.name});

  final int id;
  final String name;

  factory ClassRef.fromJson(Map<String, dynamic> json) =>
      ClassRef(id: _int(json['id']), name: '${json['name'] ?? ''}');
}

class ExamModel {
  const ExamModel({
    required this.id,
    required this.name,
    required this.academicYear,
    this.startDate,
    this.endDate,
    this.isPublished = false,
    this.classrooms = const [],
    this.subjects = const [],
    this.paperCount = 0,
  });

  final int id;
  final String name;
  final String academicYear;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPublished;
  final List<ClassRef> classrooms;
  final List<String> subjects;
  final int paperCount;

  factory ExamModel.fromJson(Map<String, dynamic> json) {
    return ExamModel(
      id: _int(json['id']),
      name: '${json['name'] ?? ''}',
      academicYear: '${json['academic_year'] ?? ''}',
      startDate: _date(json['start_date']),
      endDate: _date(json['end_date']),
      isPublished: json['is_published'] == true,
      classrooms: (json['classrooms'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClassRef.fromJson)
          .toList(),
      subjects: (json['subjects'] as List? ?? const []).map((s) => '$s').toList(),
      paperCount: _int(json['paper_count']),
    );
  }
}

class ExamPaperModel {
  const ExamPaperModel({
    required this.id,
    required this.classroomId,
    required this.classroomName,
    required this.subjectId,
    required this.subjectName,
    required this.maxMarks,
    required this.passMarks,
    this.examDate,
    this.enteredCount,
    this.canEnterMarks = false,
  });

  final int id;
  final int classroomId;
  final String classroomName;
  final int subjectId;
  final String subjectName;
  final int maxMarks;
  final int passMarks;
  final DateTime? examDate;
  final int? enteredCount;
  final bool canEnterMarks;

  factory ExamPaperModel.fromJson(Map<String, dynamic> json) {
    return ExamPaperModel(
      id: _int(json['id']),
      classroomId: _int(json['classroom']),
      classroomName: '${json['classroom_name'] ?? ''}',
      subjectId: _int(json['subject']),
      subjectName: '${json['subject_name'] ?? ''}',
      maxMarks: _int(json['max_marks'], 100),
      passMarks: _int(json['pass_marks'], 35),
      examDate: _date(json['exam_date']),
      enteredCount: _intOrNull(json['entered_count']),
      canEnterMarks: json['can_enter_marks'] == true,
    );
  }
}

/// One student's line on the mark-entry sheet.
class MarkEntry {
  MarkEntry({
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    this.marks,
    this.isAbsent = false,
  });

  final int studentId;
  final String studentName;
  final String admissionNumber;
  double? marks;
  bool isAbsent;

  factory MarkEntry.fromJson(Map<String, dynamic> json) {
    return MarkEntry(
      studentId: _int(json['student']),
      studentName: '${json['student_name'] ?? ''}',
      admissionNumber: '${json['admission_number'] ?? ''}',
      marks: _doubleOrNull(json['marks_obtained']),
      isAbsent: json['is_absent'] == true,
    );
  }

  bool get isEntered => isAbsent || marks != null;
}

class MarkSheet {
  const MarkSheet({
    required this.paper,
    required this.examName,
    required this.isPublished,
    required this.entries,
  });

  final ExamPaperModel paper;
  final String examName;
  final bool isPublished;
  final List<MarkEntry> entries;

  factory MarkSheet.fromJson(Map<String, dynamic> json) {
    return MarkSheet(
      paper: ExamPaperModel.fromJson(Map<String, dynamic>.from(json['paper'] as Map)),
      examName: '${json['exam_name'] ?? ''}',
      isPublished: json['is_published'] == true,
      entries: (json['students'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarkEntry.fromJson)
          .toList(),
    );
  }
}

class SubjectMark {
  const SubjectMark({
    required this.subject,
    required this.maxMarks,
    required this.passMarks,
    this.marks,
    this.isAbsent = false,
    this.entered = false,
    this.passed,
    this.percentage,
    this.grade,
  });

  final String subject;
  final int maxMarks;
  final int passMarks;
  final double? marks;
  final bool isAbsent;
  final bool entered;
  final bool? passed;

  /// This subject's own percentage and grade, from the backend's scale.
  final double? percentage;
  final String? grade;

  String get display => !entered ? '-' : (isAbsent ? 'AB' : formatMarks(marks));

  factory SubjectMark.fromJson(Map<String, dynamic> json) {
    return SubjectMark(
      subject: '${json['subject'] ?? ''}',
      maxMarks: _int(json['max_marks'], 100),
      passMarks: _int(json['pass_marks'], 35),
      marks: _doubleOrNull(json['marks_obtained']),
      isAbsent: json['is_absent'] == true,
      entered: json['entered'] == true,
      passed: json['passed'] as bool?,
      percentage: _doubleOrNull(json['percentage']),
      grade: json['grade']?.toString(),
    );
  }
}

/// PASS, FAIL or INCOMPLETE, as the backend computes it.
enum ExamOutcome {
  pass,
  fail,
  incomplete;

  static ExamOutcome parse(dynamic value) {
    switch ('$value'.toUpperCase()) {
      case 'PASS':
        return ExamOutcome.pass;
      case 'FAIL':
        return ExamOutcome.fail;
      default:
        return ExamOutcome.incomplete;
    }
  }

  String get label => switch (this) {
        ExamOutcome.pass => 'Pass',
        ExamOutcome.fail => 'Fail',
        ExamOutcome.incomplete => 'Incomplete',
      };
}

class ResultRow {
  const ResultRow({
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.subjects,
    required this.total,
    required this.maxTotal,
    required this.percentage,
    required this.outcome,
    this.rank,
    this.grade,
  });

  final int studentId;
  final String studentName;
  final String admissionNumber;
  final List<SubjectMark> subjects;
  final double total;
  final int maxTotal;
  final double percentage;
  final ExamOutcome outcome;
  final int? rank;

  /// Overall grade; null until every paper is entered.
  final String? grade;

  factory ResultRow.fromJson(Map<String, dynamic> json) {
    return ResultRow(
      studentId: _int(json['student']),
      studentName: '${json['student_name'] ?? ''}',
      admissionNumber: '${json['admission_number'] ?? ''}',
      subjects: (json['subjects'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SubjectMark.fromJson)
          .toList(),
      total: _doubleOrNull(json['total']) ?? 0,
      maxTotal: _int(json['max_total']),
      percentage: _doubleOrNull(json['percentage']) ?? 0,
      outcome: ExamOutcome.parse(json['result']),
      rank: _intOrNull(json['rank']),
      grade: json['grade']?.toString(),
    );
  }
}

class ClassResults {
  const ClassResults({
    required this.examName,
    required this.classroomName,
    required this.isPublished,
    required this.maxTotal,
    required this.rankedCount,
    required this.subjects,
    required this.rows,
  });

  final String examName;
  final String classroomName;
  final bool isPublished;
  final int maxTotal;
  final int rankedCount;
  final List<String> subjects;
  final List<ResultRow> rows;

  factory ClassResults.fromJson(Map<String, dynamic> json) {
    return ClassResults(
      examName: '${json['exam_name'] ?? ''}',
      classroomName: '${json['classroom_name'] ?? ''}',
      isPublished: json['is_published'] == true,
      maxTotal: _int(json['max_total']),
      rankedCount: _int(json['ranked_count']),
      subjects: (json['papers'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((p) => '${p['subject'] ?? ''}')
          .toList(),
      rows: (json['rows'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ResultRow.fromJson)
          .toList(),
    );
  }
}

/// One exam on a student's report card.
class ReportCardExam {
  const ReportCardExam({
    required this.examId,
    required this.examName,
    required this.academicYear,
    required this.classroomName,
    required this.isPublished,
    required this.subjects,
    required this.total,
    required this.maxTotal,
    required this.percentage,
    required this.outcome,
    required this.classSize,
    this.rank,
    this.startDate,
    this.grade,
  });

  final int examId;
  final String examName;
  final String academicYear;
  final String classroomName;
  final bool isPublished;
  final List<SubjectMark> subjects;
  final double total;
  final int maxTotal;
  final double percentage;
  final ExamOutcome outcome;
  final int classSize;
  final int? rank;
  final DateTime? startDate;
  final String? grade;

  factory ReportCardExam.fromJson(Map<String, dynamic> json) {
    return ReportCardExam(
      examId: _int(json['exam']),
      examName: '${json['exam_name'] ?? ''}',
      academicYear: '${json['academic_year'] ?? ''}',
      classroomName: '${json['classroom_name'] ?? ''}',
      isPublished: json['is_published'] == true,
      subjects: (json['subjects'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SubjectMark.fromJson)
          .toList(),
      total: _doubleOrNull(json['total']) ?? 0,
      maxTotal: _int(json['max_total']),
      percentage: _doubleOrNull(json['percentage']) ?? 0,
      outcome: ExamOutcome.parse(json['result']),
      classSize: _int(json['class_size']),
      rank: _intOrNull(json['rank']),
      startDate: _date(json['start_date']),
      grade: json['grade']?.toString(),
    );
  }
}

class ReportCard {
  const ReportCard({
    required this.studentName,
    required this.admissionNumber,
    this.classroomName,
    required this.exams,
  });

  final String studentName;
  final String admissionNumber;
  final String? classroomName;
  final List<ReportCardExam> exams;

  factory ReportCard.fromJson(Map<String, dynamic> json) {
    return ReportCard(
      studentName: '${json['student_name'] ?? ''}',
      admissionNumber: '${json['admission_number'] ?? ''}',
      classroomName: json['classroom_name']?.toString(),
      exams: (json['exams'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReportCardExam.fromJson)
          .toList(),
    );
  }
}


/// One step of the school's grading scale, e.g. A1 from 91%.
class GradeBand {
  const GradeBand({required this.label, required this.minPercentage, this.description = ''});

  final String label;
  final double minPercentage;
  final String description;

  factory GradeBand.fromJson(Map<String, dynamic> json) => GradeBand(
        label: '${json['label'] ?? ''}',
        minPercentage: _doubleOrNull(json['min_percentage']) ?? 0,
        description: '${json['description'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'min_percentage': minPercentage,
        'description': description,
      };
}

class GradeScale {
  const GradeScale({required this.bands, required this.isDefault});

  /// Highest band first.
  final List<GradeBand> bands;

  /// True while the school still uses the built-in default scale.
  final bool isDefault;

  factory GradeScale.fromJson(Map<String, dynamic> json) => GradeScale(
        isDefault: json['is_default'] == true,
        bands: (json['bands'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GradeBand.fromJson)
            .toList(),
      );

  /// "91-100", "81-90"... for display, from each band's lower bound.
  String rangeOf(int index) {
    final low = formatMarks(bands[index].minPercentage);
    if (index == 0) return '$low-100';
    final nextLow = bands[index - 1].minPercentage;
    final high = nextLow == nextLow.roundToDouble() ? formatMarks(nextLow - 1) : formatMarks(nextLow - 0.1);
    return '$low-$high';
  }
}
