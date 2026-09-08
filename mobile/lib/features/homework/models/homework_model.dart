class HomeworkModel {
  final int id;
  final int? classroomId;
  final String classroomName;
  final String subject;
  final String title;
  final String description;
  final String assignedByName;
  final DateTime assignedDate;
  final DateTime dueDate;
  final String? attachmentUrl;
  final bool isActive;

  const HomeworkModel({
    required this.id,
    this.classroomId,
    required this.classroomName,
    required this.subject,
    required this.title,
    required this.description,
    this.assignedByName = 'Priya Sharma',
    required this.assignedDate,
    required this.dueDate,
    this.attachmentUrl,
    this.isActive = true,
  });

  bool get isOverdue => dueDate.isBefore(DateTime.now());

  factory HomeworkModel.fromJson(Map<String, dynamic> json) {
    return HomeworkModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      classroomId: json['classroom'] is int ? json['classroom'] : null,
      classroomName: json['classroom_name'] ?? 'Grade 5 - A',
      subject: json['subject'] ?? 'General',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      assignedByName: json['assigned_by_name'] ?? 'Priya Sharma',
      assignedDate: DateTime.tryParse(json['assigned_date'] ?? '') ?? DateTime.now(),
      dueDate: DateTime.tryParse(json['due_date'] ?? '') ?? DateTime.now().add(const Duration(days: 2)),
      attachmentUrl: json['attachment_url'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'classroom': classroomId,
      'classroom_name': classroomName,
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
