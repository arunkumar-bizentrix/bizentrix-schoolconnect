class AnnouncementModel {
  final int id;
  final String title;
  final String content;
  final String priority; // 'URGENT', 'IMPORTANT', 'NORMAL'
  final String audienceType; // 'SCHOOL', 'CLASS'
  final int? targetClassId;
  final String? targetClassName;
  final String createdByName;
  final DateTime publishedAt;
  final String? attachmentUrl;
  final bool isActive;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    this.priority = 'NORMAL',
    this.audienceType = 'SCHOOL',
    this.targetClassId,
    this.targetClassName,
    this.createdByName = 'Priya Sharma (Teacher)',
    required this.publishedAt,
    this.attachmentUrl,
    this.isActive = true,
  });

  bool get isUrgent => priority.toUpperCase() == 'URGENT';
  bool get isImportant => priority.toUpperCase() == 'IMPORTANT';

  String get audienceLabel {
    if (audienceType.toUpperCase() == 'CLASS' && targetClassName != null && targetClassName!.isNotEmpty) {
      return 'For $targetClassName';
    }
    return 'For All Students';
  }

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      priority: json['priority'] ?? 'NORMAL',
      audienceType: json['audience_type'] ?? 'SCHOOL',
      targetClassId: json['target_class'] is int ? json['target_class'] : null,
      targetClassName: json['target_class_name'],
      createdByName: json['created_by_name'] ?? 'School Administration',
      publishedAt: DateTime.tryParse(json['published_at'] ?? '') ?? DateTime.now(),
      attachmentUrl: json['attachment_url'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'priority': priority,
      'audience_type': audienceType,
      'target_class': targetClassId,
      'target_class_name': targetClassName,
      'attachment_url': attachmentUrl,
      'is_active': isActive,
    };
  }
}
