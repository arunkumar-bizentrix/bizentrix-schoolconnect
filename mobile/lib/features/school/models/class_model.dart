import '../../../core/constants/app_constants.dart';

class ClassModel {
  final int id;
  final String name;
  final String section;
  final String academicYear;
  final String displayName;
  final String teacherName;
  final int studentCount;
  final bool isActive;

  const ClassModel({
    required this.id,
    required this.name,
    required this.section,
    required this.academicYear,
    required this.displayName,
    this.teacherName = 'Not Assigned',
    this.studentCount = 0,
    this.isActive = true,
  });

  String get shortCode => '${name.replaceAll(RegExp(r'[^0-9]'), '')}$section';

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    final nameStr = json['name'] ?? '';
    final sectionStr = json['section'] ?? '';
    final display = json['display_name'] ?? '$nameStr - $sectionStr';

    String teacher = 'Not Assigned';
    if (json['teacher_names'] is List && (json['teacher_names'] as List).isNotEmpty) {
      teacher = (json['teacher_names'] as List).join(', ');
    } else if (json['teacher_name'] != null && json['teacher_name'].toString().isNotEmpty) {
      teacher = json['teacher_name'].toString();
    }

    final count = json['student_count'] is int
        ? json['student_count'] as int
        : int.tryParse(json['student_count']?.toString() ?? '0') ?? 0;

    return ClassModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: nameStr,
      section: sectionStr,
      academicYear: json['academic_year'] ?? AppConstants.currentAcademicYear,
      displayName: display,
      teacherName: teacher,
      studentCount: count,
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'section': section,
      'academic_year': academicYear,
      'display_name': displayName,
      'is_active': isActive,
    };
  }
}
