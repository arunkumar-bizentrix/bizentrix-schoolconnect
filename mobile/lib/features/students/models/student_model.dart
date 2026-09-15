import '../../../core/constants/app_constants.dart';

class StudentModel {
  final int id;
  final String admissionNumber;
  final String firstName;
  final String lastName;
  final String fullName;
  final int? classId;
  final String className;
  final String academicYear;
  final List<int> parentIds;
  final List<String> parentNames;
  final bool isActive;

  const StudentModel({
    required this.id,
    required this.admissionNumber,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    this.classId,
    required this.className,
    this.academicYear = AppConstants.currentAcademicYear,
    this.parentIds = const [],
    this.parentNames = const [],
    this.isActive = true,
  });

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    final first = json['first_name'] ?? '';
    final last = json['last_name'] ?? '';
    final full = json['full_name'] ?? '$first $last'.trim();

    int? cId;
    if (json['class_enrolled'] is int) {
      cId = json['class_enrolled'];
    } else if (json['class_enrolled'] is Map) {
      cId = json['class_enrolled']['id'];
    } else if (json['class_enrolled'] != null) {
      cId = int.tryParse(json['class_enrolled'].toString());
    }

    final rawParents = json['parents'];
    final parentIds = rawParents is List
        ? rawParents
            .map((p) => p is int ? p : int.tryParse(p.toString()) ?? 0)
            .where((p) => p > 0)
            .toList()
        : <int>[];

    return StudentModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      admissionNumber: json['admission_number'] ?? 'ADM000',
      firstName: first,
      lastName: last,
      fullName: full.isEmpty ? 'Student' : full,
      classId: cId,
      className: json['class_name'] ?? json['class_enrolled_name'] ?? 'Class',
      academicYear: json['academic_year'] ?? AppConstants.currentAcademicYear,
      parentIds: parentIds,
      parentNames: (json['parent_names'] as List<dynamic>? ?? const [])
          .map((name) => name.toString())
          .where((name) => name.trim().isNotEmpty)
          .toList(),
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'admission_number': admissionNumber,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'class_enrolled': classId,
      'class_name': className,
      'academic_year': academicYear,
      'parents': parentIds,
      'parent_names': parentNames,
      'is_active': isActive,
    };
  }
}
