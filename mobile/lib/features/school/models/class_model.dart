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
    this.teacherName = 'Priya Sharma',
    this.studentCount = 32,
    this.isActive = true,
  });

  String get shortCode => '${name.replaceAll(RegExp(r'[^0-9]'), '')}$section';

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    final nameStr = json['name'] ?? '';
    final sectionStr = json['section'] ?? '';
    final display = json['display_name'] ?? '$nameStr - $sectionStr';

    return ClassModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: nameStr,
      section: sectionStr,
      academicYear: json['academic_year'] ?? '2025-2026',
      displayName: display,
      teacherName: json['teacher_name'] ?? 'Priya Sharma',
      studentCount: json['student_count'] ?? (sectionStr == 'A' ? 32 : 16),
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
