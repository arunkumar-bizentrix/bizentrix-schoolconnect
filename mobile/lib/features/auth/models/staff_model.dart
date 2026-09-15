/// A teacher or parent account, as the admin sees it.
///
/// Comes from GET /api/v1/auth/staff/?role=TEACHER|PARENT (admin only) and
/// backs both the People screen and the pickers (assigning a teacher to a
/// class, linking a parent to a student).
class StaffModel {
  final int id;
  final String username;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String role;
  final bool isActive;

  /// A teacher's classes, or a parent's children - what makes a row
  /// recognisable at a glance.
  final List<String> linked;

  const StaffModel({
    required this.id,
    required this.fullName,
    this.username = '',
    this.email = '',
    this.phoneNumber = '',
    this.role = '',
    this.isActive = true,
    this.linked = const [],
  });

  bool get isTeacher => role == 'TEACHER';

  /// Name plus whichever contact detail exists, for disambiguating two
  /// teachers with the same name.
  String get subtitle {
    if (phoneNumber.isNotEmpty) return phoneNumber;
    if (email.isNotEmpty) return email;
    return role;
  }

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory StaffModel.fromJson(Map<String, dynamic> json) {
    return StaffModel(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phoneNumber: (json['phone_number'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      isActive: json['is_active'] != false,
      linked: (json['linked'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}
