import '../../homework/models/homework_model.dart';

class AnnouncementModel {
  final String id;
  final String title;
  final String content;
  final String priority; // 'normal', 'urgent'
  final String targetAudience; // 'all', 'parents', 'teachers'
  final String authorName;
  final DateTime createdAt;
  final List<AttachmentModel> attachments;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    this.priority = 'normal',
    this.targetAudience = 'all',
    required this.authorName,
    required this.createdAt,
    this.attachments = const [],
  });

  bool get isUrgent => priority.toLowerCase() == 'urgent';

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      priority: json['priority'] ?? 'normal',
      targetAudience: json['target_audience'] ?? 'all',
      authorName: json['author_name'] ?? 'School Administration',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
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
      'content': content,
      'priority': priority,
      'target_audience': targetAudience,
      'author_name': authorName,
      'created_at': createdAt.toIso8601String(),
      'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }
}
