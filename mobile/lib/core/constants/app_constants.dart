/// Global application constants and configuration values.
class AppConstants {
  static const String appName = 'Bizentrix SchoolConnect';
  static const String appVersion = '1.0.0';

  // Base API configuration (configurable for local dev vs production)
  // For Android emulator: 10.0.2.2 points to host machine localhost
  // For real Android device: use LAN IP (e.g., 192.168.x.x) or production URL
  static const String defaultBaseUrl = 'http://10.0.2.2:8000/api/v1';

  // Local & Secure Storage Keys
  static const String tokenKey = 'jwt_access_token';
  static const String refreshTokenKey = 'jwt_refresh_token';
  static const String userRoleKey = 'current_user_role';
  static const String userProfileKey = 'user_profile_data';
  static const String activeSchoolIdKey = 'active_school_id';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}

/// System user roles
enum UserRole {
  admin('admin', 'Administrator'),
  teacher('teacher', 'Teacher'),
  parent('parent', 'Parent');

  final String code;
  final String label;

  const UserRole(this.code, this.label);

  static UserRole fromCode(String? code) {
    return UserRole.values.firstWhere(
      (role) => role.code.toLowerCase() == code?.toLowerCase(),
      orElse: () => UserRole.parent,
    );
  }
}
