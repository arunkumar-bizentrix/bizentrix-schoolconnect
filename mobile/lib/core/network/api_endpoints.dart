class ApiEndpoints {
  // Authentication & Profile
  static const String login = '/auth/token/';
  static const String refreshToken = '/auth/token/refresh/';
  static const String userProfile = '/auth/me/';
  static const String sendOtp = '/auth/otp/send/';
  static const String verifyOtp = '/auth/otp/verify/';
  static const String authOtpEmailSend = '/auth/otp/email/send/';
  static const String authOtpEmailVerify = '/auth/otp/email/verify/';

  // School & Academic Structure
  static const String schools = '/schools/';
  static const String classes = '/classes/';
  static String classDetail(dynamic id) => '/classes/$id/';

  static const String students = '/students/';
  static String studentDetail(dynamic id) => '/students/$id/';

  // Homework
  static const String homeworkList = '/homework/';
  static String homeworkDetail(dynamic id) => '/homework/$id/';
  static String homeworkSubmissions(dynamic id) => '/homework/$id/submissions/';

  // Announcements
  static const String announcements = '/announcements/';
  static String announcementDetail(dynamic id) => '/announcements/$id/';

  // Parent Children
  static const String parentChildren = '/parent/children/';

  // Attachments
  static const String uploadAttachment = '/attachments/upload/';

  // Notifications
  static const String notifications = '/notifications/';
  static String notificationRead(dynamic id) => '/notifications/$id/read/';
  static const String notificationsMarkAllRead = '/notifications/mark-all-read/';
  static const String notificationsUnreadCount = '/notifications/unread-count/';
  static const String registerDevice = '/notifications/register-device/';
}

