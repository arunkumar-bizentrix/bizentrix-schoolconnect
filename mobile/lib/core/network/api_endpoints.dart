/// Every backend route the app talks to, in one place.
/// Keep this in sync with backend/config/urls.py and the app URL modules.
class ApiEndpoints {
  // Authentication & Profile
  static const String login = '/auth/token/';
  static const String refreshToken = '/auth/token/refresh/';
  static const String userProfile = '/auth/me/';
  static const String changePassword = '/auth/change-password/';
  static const String schoolStaff = '/auth/staff/';
  static String staffDetail(dynamic id) => '/auth/staff/$id/';
  static String staffResetPassword(dynamic id) => '/auth/staff/$id/reset-password/';
  static const String sendOtp = '/auth/otp/send/';
  static const String verifyOtp = '/auth/otp/verify/';
  static const String authOtpEmailSend = '/auth/otp/email/send/';
  static const String authOtpEmailVerify = '/auth/otp/email/verify/';

  // School & Academic Structure
  static const String classes = '/classes/';
  static String classDetail(dynamic id) => '/classes/$id/';

  static const String students = '/students/';
  static const String studentImport = '/students/import/';
  static String studentDetail(dynamic id) => '/students/$id/';
  static String studentLinkParent(dynamic id) => '/students/$id/link-parent/';
  static String studentUnlinkParent(dynamic id) => '/students/$id/unlink-parent/';

  // Homework
  static const String homeworkList = '/homework/';
  static String homeworkDetail(dynamic id) => '/homework/$id/';

  // Announcements
  static const String announcements = '/announcements/';
  static String announcementDetail(dynamic id) => '/announcements/$id/';

  // Parent Children
  static const String parentChildren = '/parent/children/';
  static const String parentToday = '/parent/today/';

  // Monitoring
  static const String dashboardSummary = '/dashboard/summary/';
  static String studentProfile(dynamic id) => '/students/$id/profile/';
  static String classOverview(dynamic id) => '/classes/$id/overview/';
  static String teacherProfile(dynamic id) => '/auth/staff/$id/profile/';

  // Messages
  static const String conversations = '/messages/conversations/';
  static String conversation(dynamic id) => '/messages/conversations/$id/';
  static String conversationMessages(dynamic id) => '/messages/conversations/$id/messages/';
  static const String messageContacts = '/messages/contacts/';
  static const String messagesUnreadCount = '/messages/unread-count/';

  // Subjects & Timetable
  static const String subjects = '/subjects/';
  static const String timetable = '/timetable/';
  static const String timetableWeek = '/timetable/week/';
  static const String timetableMine = '/timetable/my/';
  static const String timetableToday = '/timetable/today/';

  // Attendance
  static const String attendance = '/attendance/';
  static const String attendanceMark = '/attendance/mark/';
  static const String attendanceSheet = '/attendance/sheet/';
  static const String attendanceSummary = '/attendance/summary/';

  // Exams, marks & report cards
  static const String exams = '/exams/';
  static String examDetail(dynamic id) => '/exams/$id/';
  static String examPapers(dynamic id) => '/exams/$id/papers/';
  static String examResults(dynamic id) => '/exams/$id/results/';
  static String examProgress(dynamic id) => '/exams/$id/progress/';
  static String examPublish(dynamic id) => '/exams/$id/publish/';
  static String examUnpublish(dynamic id) => '/exams/$id/unpublish/';
  static String examPaperDetail(dynamic id) => '/exam-papers/$id/';
  static String examPaperMarks(dynamic id) => '/exam-papers/$id/marks/';
  static const String reportCard = '/report-card/';
  static String reportCardPdf(int studentId, {int? examId}) =>
      '/report-card/pdf/?student_id=$studentId${examId == null ? '' : '&exam_id=$examId'}';
  static const String gradeScale = '/grade-scale/';

  // Notifications
  static const String notifications = '/notifications/';
  static String notificationRead(dynamic id) => '/notifications/$id/read/';
  static const String notificationsMarkAllRead = '/notifications/mark-all-read/';
  static const String notificationsUnreadCount = '/notifications/unread-count/';
  static const String registerDevice = '/notifications/register-device/';
}
