import '../../../core/constants/app_constants.dart';

class HomeworkModel {
  final int id;
  final int? classId;
  final String className;
  final int? studentId;
  final String? studentName;
  final String subject;
  final String title;
  final String description;
  final String assignedByName;
  final DateTime assignedDate;
  final DateTime dueDate;
  final String? attachmentUrl;
  final String academicYear;
  final bool isActive;

  const HomeworkModel({
    required this.id,
    this.classId,
    required this.className,
    this.studentId,
    this.studentName,
    required this.subject,
    required this.title,
    required this.description,
    this.assignedByName = 'Faculty',
    required this.assignedDate,
    required this.dueDate,
    this.attachmentUrl,
    this.academicYear = AppConstants.currentAcademicYear,
    this.isActive = true,
  });

  bool get isOverdue => dueDate.isBefore(DateTime.now());

  factory HomeworkModel.fromJson(Map<String, dynamic> json) {
    int? cId;
    if (json['classroom'] is int) {
      cId = json['classroom'];
    } else if (json['classroom'] is Map) {
      cId = json['classroom']['id'];
    } else if (json['classroom'] != null) {
      cId = int.tryParse(json['classroom'].toString());
    }

    int? sId;
    if (json['student'] is int) {
      sId = json['student'];
    } else if (json['student'] is Map) {
      sId = json['student']['id'];
    } else if (json['student'] != null) {
      sId = int.tryParse(json['student'].toString());
    }

    return HomeworkModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      classId: cId,
      className: json['classroom_name'] ?? 'Class',
      studentId: sId,
      studentName: json['student_name'],
      subject: json['subject'] ?? 'General',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      assignedByName: json['assigned_by_name'] ?? 'Faculty',
      assignedDate: DateTime.tryParse(json['assigned_date'] ?? '') ?? DateTime.now(),
      dueDate: DateTime.tryParse(json['due_date'] ?? '') ?? DateTime.now().add(const Duration(days: 2)),
      attachmentUrl: json['attachment'] ?? json['attachment_url'],
      academicYear: json['academic_year'] ?? AppConstants.currentAcademicYear,
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'classroom': classId,
      'classroom_name': className,
      'subject': subject,
      'title': title,
      'description': description,
      'assigned_date': assignedDate.toIso8601String().split('T').first,
      'due_date': dueDate.toIso8601String().split('T').first,
      'attachment_url': attachmentUrl,
      'is_active': isActive,
    };
  }
}
