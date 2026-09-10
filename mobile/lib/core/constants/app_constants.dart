/// Global application constants and configuration values.
class AppConstants {
  static const String appName = 'Vivekananda School';
  static const String appVersion = '1.0.0';

  // School Institutional Identity & Branding (https://swamyviv.com)
  static const String schoolName = 'Vivekananda School';
  static const String schoolBranch = 'Bagalur';
  static const String schoolFullName = 'Vivekananda School, Bagalur';
  static const String schoolCode = 'VIV001';
  static const String schoolTagline = 'Shaping Future Leaders with Care & Excellence';
  static const String schoolMotto = 'Safe, value-based education for holistic growth';
  static const String schoolEstablished = 'Excellence Since 1999';
  static const String schoolAddress = 'Jogikalasanapalli, Bagalur, Tamil Nadu 635103';
  static const String schoolPhone = '+91 94439 40772';
  static const String schoolEmail = 'vivekanandaschoolbagalur@gmail.com';
  static const String schoolWebsite = 'https://swamyviv.com/';
  static const String schoolLogoPath = 'assets/images/school_logo.png';
  static const String schoolCampusPath = 'assets/images/school_campus.jpg';

  // Base API configuration (Wi-Fi LAN IP or adb reverse fallback)
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.0.6:8000/api/v1',
  );
  static const String fallbackBaseUrl = 'http://127.0.0.1:8000/api/v1';

  // Local & Secure Storage Keys
  static const String tokenKey = 'jwt_access_token';
  static const String refreshTokenKey = 'jwt_refresh_token';
  static const String userRoleKey = 'current_user_role';
  static const String userProfileKey = 'user_profile_data';
  static const String baseUrlOverrideKey = 'custom_api_base_url';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Academic year used for all list queries until a session picker exists.
  static const String currentAcademicYear = '2026-2027';
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
