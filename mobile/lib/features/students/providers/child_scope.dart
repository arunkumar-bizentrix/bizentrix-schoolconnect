import '../../announcements/models/announcement_model.dart';
import '../../homework/models/homework_model.dart';
import '../models/student_model.dart';

/// Narrows lists fetched for a parent down to a single selected child.
///
/// A parent with several children receives the union of their homework and
/// notices from the API - the backend scopes to "this parent's children", not
/// to "the child currently selected in the UI". Picking one child is a
/// presentation concern, but the rule for what belongs to that child is domain
/// logic, so it lives here rather than inside a dashboard widget.
class ChildScope {
  const ChildScope._();

  /// Homework visible for [child]: items addressed to the child's class.
  /// With no child selected, nothing is filtered out.
  static List<HomeworkModel> homeworkFor(
    List<HomeworkModel> homework,
    StudentModel? child,
  ) {
    if (child == null || child.classId == null) return homework;
    return homework
        .where((item) => item.classId == child.classId)
        .toList();
  }

  /// Announcements visible for [child]: school-wide circulars always, plus
  /// class-targeted notices for the child's own class.
  static List<AnnouncementModel> announcementsFor(
    List<AnnouncementModel> announcements,
    StudentModel? child,
  ) {
    if (child == null || child.classId == null) return announcements;
    return announcements.where((notice) {
      if (!notice.isClassTargeted) return true;
      return notice.targetClassId == child.classId;
    }).toList();
  }
}
