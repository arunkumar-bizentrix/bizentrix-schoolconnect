import '../../exams/models/exam_models.dart';
import '../../timetable/models/timetable_model.dart';

int _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
double? _double(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');
List<Map<String, dynamic>> _rows(dynamic v) => (v as List? ?? const []).whereType<Map<String, dynamic>>().toList();
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Real school-wide totals from GET /dashboard/summary/.
class DashboardSummary {
  const DashboardSummary(this.json);

  final Map<String, dynamic> json;

  Map<String, dynamic> get _counts => _map(json['counts']);
  Map<String, dynamic> get _today => _map(json['attendance_today']);
  Map<String, dynamic> get _attention => _map(json['needs_attention']);

  int get students => _int(_counts['students']);
  int get classes => _int(_counts['classes']);
  int get teachers => _int(_counts['teachers']);
  int get parents => _int(_counts['parents']);

  int get classesMarkedToday => _int(_today['classes_marked']);
  int get classesTotal => _int(_today['classes_total']);
  int get presentToday => _int(_today['present']) + _int(_today['late']);
  int get absentToday => _int(_today['absent']);

  int get examsPublished => _int(_map(json['exams'])['published']);
  int get examsDraft => _int(_map(json['exams'])['draft']);
  int get activeHomework => _int(_map(json['homework'])['active']);
  int get announcementsThisWeek => _int(json['announcements_last_7_days']);

  int get teachersWithoutClass => _int(_attention['teachers_without_class']);
  int get classesWithoutClassTeacher => _int(_attention['classes_without_class_teacher']);
  int get studentsWithoutClass => _int(_attention['students_without_class']);
  int get studentsWithoutParent => _int(_attention['students_without_parent']);

  bool get needsAttention =>
      teachersWithoutClass + classesWithoutClassTeacher + studentsWithoutClass + studentsWithoutParent > 0;
}

class AttendanceDay {
  const AttendanceDay({required this.date, required this.status, this.note = ''});

  final DateTime? date;
  final String status;
  final String note;

  factory AttendanceDay.fromJson(Map<String, dynamic> json) =>
      AttendanceDay(date: _date(json['date']), status: '${json['status'] ?? ''}', note: '${json['note'] ?? ''}');
}

class ProfileResult {
  const ProfileResult(this.json);

  final Map<String, dynamic> json;

  int get examId => _int(json['exam']);
  String get examName => '${json['exam_name'] ?? ''}';
  String get academicYear => '${json['academic_year'] ?? ''}';
  String get classroomName => '${json['classroom_name'] ?? ''}';
  double get total => _double(json['total']) ?? 0;
  int get maxTotal => _int(json['max_total']);
  double get percentage => _double(json['percentage']) ?? 0;
  String? get grade => json['grade']?.toString();
  ExamOutcome get outcome => ExamOutcome.parse(json['result']);
  int? get rank => json['rank'] == null ? null : _int(json['rank']);
  int get classSize => _int(json['class_size']);
  bool get isPublished => json['is_published'] == true;
}

/// GET /students/{id}/profile/
class StudentProfile {
  const StudentProfile(this.json);

  final Map<String, dynamic> json;

  Map<String, dynamic> get _student => _map(json['student']);
  Map<String, dynamic>? get _classroom => json['classroom'] is Map ? _map(json['classroom']) : null;
  Map<String, dynamic> get _attendance => _map(json['attendance']);

  int get id => _int(_student['id']);
  String get fullName => '${_student['full_name'] ?? ''}';
  String get admissionNumber => '${_student['admission_number'] ?? ''}';
  DateTime? get dateOfBirth => _date(_student['date_of_birth']);

  String? get className => _classroom == null ? null : '${_classroom!['name']} - ${_classroom!['section']}';
  String? get academicYear => _classroom?['academic_year']?.toString();
  String? get classTeacherName => _classroom?['class_teacher_name']?.toString();
  int? get classTeacherId => _classroom?['class_teacher_id'] == null ? null : _int(_classroom!['class_teacher_id']);

  List<({int id, String name, String phone, String email})> get parents => [
        for (final p in _rows(json['parents']))
          (id: _int(p['id']), name: '${p['full_name'] ?? ''}', phone: '${p['phone_number'] ?? ''}', email: '${p['email'] ?? ''}'),
      ];

  double? get attendancePercentage => _double(_attendance['percentage']);
  int get daysRecorded => _int(_attendance['days_recorded']);
  int get daysPresent => _int(_attendance['present']);
  int get daysAbsent => _int(_attendance['absent']);
  int get daysLate => _int(_attendance['late']);
  List<AttendanceDay> get recentAttendance => _rows(_attendance['recent']).map(AttendanceDay.fromJson).toList();

  int get activeHomework => _int(_map(json['homework'])['active']);
  List<({String title, String subject, String due, bool onlyThisChild})> get recentHomework => [
        for (final h in _rows(_map(json['homework'])['recent']))
          (
            title: '${h['title'] ?? ''}',
            subject: '${h['subject'] ?? ''}',
            due: '${h['due_display'] ?? ''}',
            onlyThisChild: h['is_for_this_child_only'] == true,
          ),
      ];

  List<ProfileResult> get results => _rows(json['results']).map(ProfileResult.new).toList();

  List<({String year, String className, bool current})> get classHistory => [
        for (final c in _rows(json['class_history']))
          (year: '${c['academic_year'] ?? ''}', className: '${c['classroom_name'] ?? ''}', current: c['is_current'] == true),
      ];
}

/// GET /classes/{id}/overview/
class ClassOverview {
  const ClassOverview(this.json);

  final Map<String, dynamic> json;

  Map<String, dynamic> get _class => _map(json['classroom']);
  Map<String, dynamic> get _today => _map(json['attendance_today']);

  int get id => _int(_class['id']);
  String get name => '${_class['name']} - ${_class['section']}';
  String get academicYear => '${_class['academic_year'] ?? ''}';
  int get studentCount => _int(_class['student_count']);
  String? get classTeacherName => json['class_teacher'] is Map ? '${_map(json['class_teacher'])['full_name']}' : null;

  List<({int id, String name, bool isClassTeacher})> get teachers => [
        for (final t in _rows(json['teachers']))
          (id: _int(t['id']), name: '${t['full_name'] ?? ''}', isClassTeacher: t['is_class_teacher'] == true),
      ];

  List<({String subject, List<String> teachers, int periods})> get subjects => [
        for (final s in _rows(json['subjects']))
          (
            subject: '${s['subject_name'] ?? ''}',
            teachers: (s['teachers'] as List? ?? const []).map((t) => '$t').toList(),
            periods: _int(s['periods_per_week']),
          ),
      ];

  bool get attendanceMarkedToday => _today['is_marked'] == true;
  int get presentToday => _int(_today['present']) + _int(_today['late']);
  int get absentToday => _int(_today['absent']);
  int get notMarkedToday => _int(_today['not_marked']);

  List<({int id, String name, String admission, double? attendance, int parents})> get students => [
        for (final s in _rows(json['students']))
          (
            id: _int(s['id']),
            name: '${s['full_name'] ?? ''}',
            admission: '${s['admission_number'] ?? ''}',
            attendance: _double(s['attendance_percentage']),
            parents: _int(s['parent_count']),
          ),
      ];

  int get activeHomework => _int(_map(json['homework'])['active']);
  List<({String title, String subject, String due, String by})> get recentHomework => [
        for (final h in _rows(_map(json['homework'])['recent']))
          (title: '${h['title'] ?? ''}', subject: '${h['subject'] ?? ''}', due: '${h['due_display'] ?? ''}',
              by: '${h['assigned_by_name'] ?? ''}'),
      ];

  List<({int id, String name, bool published})> get exams => [
        for (final e in _rows(json['exams'])) (id: _int(e['id']), name: '${e['name'] ?? ''}', published: e['is_published'] == true),
      ];
}

/// GET /auth/staff/{id}/profile/
class TeacherProfile {
  const TeacherProfile(this.json);

  final Map<String, dynamic> json;

  Map<String, dynamic> get _teacher => _map(json['teacher']);
  Map<String, dynamic> get _activity => _map(json['activity_last_30_days']);

  int get id => _int(_teacher['id']);
  String get fullName => '${_teacher['full_name'] ?? ''}';
  String get phone => '${_teacher['phone_number'] ?? ''}';
  String get email => '${_teacher['email'] ?? ''}';
  bool get isActive => _teacher['is_active'] != false;

  List<({int id, String name, bool isClassTeacher, int students})> get classes => [
        for (final c in _rows(json['classes']))
          (id: _int(c['id']), name: '${c['name'] ?? ''}', isClassTeacher: c['is_class_teacher'] == true, students: _int(c['student_count'])),
      ];

  List<({String subject, List<String> classes, int periods})> get subjects => [
        for (final s in _rows(json['subjects']))
          (
            subject: '${s['subject_name'] ?? ''}',
            classes: (s['classes'] as List? ?? const []).map((c) => '$c').toList(),
            periods: _int(s['periods_per_week']),
          ),
      ];

  TimetableWeek get timetable => TimetableWeek.fromJson({'days': json['timetable'] ?? const []});

  int get homeworkSet => _int(_activity['homework_set']);
  int get attendanceDaysMarked => _int(_activity['attendance_days_marked']);
  int get announcementsPosted => _int(_activity['announcements_posted']);
  int get marksEntered => _int(_activity['marks_entered']);
  List<({String title, String subject, String className})> get recentHomework => [
        for (final h in _rows(_activity['recent_homework']))
          (title: '${h['title'] ?? ''}', subject: '${h['subject'] ?? ''}', className: '${h['classroom_name'] ?? ''}'),
      ];
}
