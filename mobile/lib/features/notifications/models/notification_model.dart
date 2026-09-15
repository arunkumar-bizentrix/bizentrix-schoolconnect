class NotificationModel {
  final int id;
  final String notificationType;
  final String title;
  final String message;
  final int? homeworkId;
  final int? announcementId;
  final int? attendanceId;
  final int? targetId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.notificationType,
    required this.title,
    required this.message,
    this.homeworkId,
    this.announcementId,
    this.attendanceId,
    this.targetId,
    this.isRead = false,
    required this.createdAt,
  });

  bool get isHomework => notificationType == 'HOMEWORK';
  bool get isAnnouncement => notificationType == 'ANNOUNCEMENT';
  bool get isAttendance => notificationType == 'ATTENDANCE';

  /// Attendance notices about an absence are the ones a parent must not miss.
  bool get isAbsence =>
      isAttendance && title.toLowerCase().contains('absent');

  NotificationModel copyWith({
    int? id,
    String? notificationType,
    String? title,
    String? message,
    int? homeworkId,
    int? announcementId,
    int? attendanceId,
    int? targetId,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      notificationType: notificationType ?? this.notificationType,
      title: title ?? this.title,
      message: message ?? this.message,
      homeworkId: homeworkId ?? this.homeworkId,
      announcementId: announcementId ?? this.announcementId,
      attendanceId: attendanceId ?? this.attendanceId,
      targetId: targetId ?? this.targetId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int? ?? 0,
      notificationType: json['notification_type'] as String? ?? 'GENERAL',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      homeworkId: json['homework'] as int?,
      announcementId: json['announcement'] as int?,
      attendanceId: json['attendance'] as int?,
      targetId: json['target_id'] as int?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'notification_type': notificationType,
      'title': title,
      'message': message,
      'homework': homeworkId,
      'announcement': announcementId,
      'attendance': attendanceId,
      'target_id': targetId,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
