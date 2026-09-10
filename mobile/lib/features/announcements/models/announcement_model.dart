import '../../../core/constants/app_constants.dart';

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
  final String academicYear;
  final bool isActive;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    this.priority = 'NORMAL',
    this.audienceType = 'SCHOOL',
    this.targetClassId,
    this.targetClassName,
    this.createdByName = 'School Administration',
    required this.publishedAt,
    this.attachmentUrl,
    this.academicYear = AppConstants.currentAcademicYear,
    this.isActive = true,
  });

  bool get isUrgent => priority.toUpperCase() == 'URGENT';
  bool get isImportant => priority.toUpperCase() == 'IMPORTANT';
  bool get isClassTargeted => audienceType.toUpperCase() == 'CLASS';

  String get audienceLabel {
    if (audienceType.toUpperCase() == 'CLASS' && targetClassName != null && targetClassName!.isNotEmpty) {
      return 'For $targetClassName';
    }
    if (audienceType.toUpperCase() == 'PARENTS') {
      return 'For Parents Only';
    }
    return 'For All Students';
  }

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    int? tcId;
    if (json['target_class'] is int) {
      tcId = json['target_class'];
    } else if (json['target_class'] is Map) {
      tcId = json['target_class']['id'];
    } else if (json['target_class'] != null) {
      tcId = int.tryParse(json['target_class'].toString());
    }

    return AnnouncementModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      priority: json['priority'] ?? 'NORMAL',
      audienceType: json['audience_type'] ?? 'SCHOOL',
      targetClassId: tcId,
      targetClassName: json['target_class_name'],
      createdByName: json['created_by_name'] ?? 'School Administration',
      publishedAt: DateTime.tryParse(json['published_at'] ?? '') ?? DateTime.now(),
      attachmentUrl: json['attachment'] ?? json['attachment_url'],
      academicYear: json['academic_year'] ?? AppConstants.currentAcademicYear,
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
