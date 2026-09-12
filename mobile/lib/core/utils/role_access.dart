import '../constants/app_constants.dart';

/// What each role is allowed to do, in one place.
///
/// These mirror the backend permission classes exactly (see
/// docs/ARCHITECTURE.md - Role system). The UI uses them to hide actions the
/// user cannot perform; the backend remains the authority and re-checks every
/// request. Never treat a `true` here as authorization on its own.
extension RoleAccess on UserRole {
  bool get isAdmin => this == UserRole.admin;
  bool get isTeacher => this == UserRole.teacher;
  bool get isParent => this == UserRole.parent;

  /// Classes and students are administrative records. Teachers read the ones
  /// they are assigned to; parents read the ones their children belong to.
  bool get canManageClasses => isAdmin;
  bool get canManageStudents => isAdmin;

  /// Linking parents to students, and teachers to classes.
  bool get canManageParentLinks => isAdmin;
  bool get canManageTeacherAssignments => isAdmin;

  /// Homework is the teacher's workspace, scoped to their assigned classes.
  bool get canManageHomework => isAdmin || isTeacher;

  /// Teachers may post to their own classes; only admins post school-wide.
  bool get canManageAnnouncements => isAdmin || isTeacher;
  bool get canPostSchoolWideAnnouncements => isAdmin;
}

/// Convenience for the common `user?.role` nullable case: an unknown role can
/// do nothing.
extension NullableRoleAccess on UserRole? {
  bool get isAdmin => this == UserRole.admin;
  bool get isTeacher => this == UserRole.teacher;
  bool get isParent => this == UserRole.parent;

  bool get canManageClasses => this?.canManageClasses ?? false;
  bool get canManageStudents => this?.canManageStudents ?? false;
  bool get canManageParentLinks => this?.canManageParentLinks ?? false;
  bool get canManageTeacherAssignments => this?.canManageTeacherAssignments ?? false;
  bool get canManageHomework => this?.canManageHomework ?? false;
  bool get canManageAnnouncements => this?.canManageAnnouncements ?? false;
  bool get canPostSchoolWideAnnouncements => this?.canPostSchoolWideAnnouncements ?? false;
}
