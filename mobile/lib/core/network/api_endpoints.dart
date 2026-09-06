class ApiEndpoints {
  // Authentication & Profile
  static const String login = '/auth/login/';
  static const String refreshToken = '/auth/token/refresh/';
  static const String userProfile = '/auth/me/';
  static const String logout = '/auth/logout/';

  // School & Academic Structure
  static const String schools = '/schools/';
  static const String classes = '/classes/';
  static const String students = '/students/';

  // Homework
  static const String homeworkList = '/homework/';
  static String homeworkDetail(String id) => '/homework/$id/';
  static String homeworkSubmissions(String id) => '/homework/$id/submissions/';

  // Announcements
  static const String announcements = '/announcements/';
  static String announcementDetail(String id) => '/announcements/$id/';

  // Attachments
  static const String uploadAttachment = '/attachments/upload/';

  // Notifications (FCM token registration)
  static const String registerDevice = '/notifications/register-device/';
}
