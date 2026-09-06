class AttachmentModel {
  final String id;
  final String fileName;
  final String fileUrl;
  final String fileType; // 'pdf', 'image', etc.
  final int? fileSize;

  const AttachmentModel({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    required this.fileType,
    this.fileSize,
  });

  factory AttachmentModel.fromJson(Map<String, dynamic> json) {
    return AttachmentModel(
      id: json['id']?.toString() ?? '',
      fileName: json['file_name'] ?? 'attachment',
      fileUrl: json['file_url'] ?? '',
      fileType: json['file_type'] ?? 'unknown',
      fileSize: json['file_size'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'file_url': fileUrl,
      'file_type': fileType,
      'file_size': fileSize,
    };
  }
}

class HomeworkModel {
  final String id;
  final String title;
  final String description;
  final String subject;
  final String className;
  final DateTime dueDate;
  final DateTime createdAt;
  final String teacherName;
  final List<AttachmentModel> attachments;

  const HomeworkModel({
    required this.id,
    required this.title,
    required this.description,
    required this.subject,
    required this.className,
    required this.dueDate,
    required this.createdAt,
    required this.teacherName,
    this.attachments = const [],
  });

  factory HomeworkModel.fromJson(Map<String, dynamic> json) {
    return HomeworkModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      subject: json['subject'] ?? '',
      className: json['class_name'] ?? '',
      dueDate: DateTime.tryParse(json['due_date'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      teacherName: json['teacher_name'] ?? '',
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((item) => AttachmentModel.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'subject': subject,
      'class_name': className,
      'due_date': dueDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'teacher_name': teacherName,
      'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }
}
