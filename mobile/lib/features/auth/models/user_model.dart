import '../../../core/constants/app_constants.dart';

class UserModel {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? schoolId;
  final String? schoolName;
  final String? phoneNumber;
  final String? avatarUrl;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.schoolId,
    this.schoolName,
    this.phoneNumber,
    this.avatarUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    String? schoolId;
    String? schoolName;
    if (json['school'] is Map) {
      final schoolMap = json['school'] as Map;
      schoolId = schoolMap['id']?.toString();
      schoolName = schoolMap['name']?.toString();
    } else if (json['school'] != null) {
      schoolId = json['school']?.toString();
      schoolName = json['school_name']?.toString();
    } else {
      schoolId = json['school_id']?.toString();
      schoolName = json['school_name']?.toString();
    }

    final role = UserRole.fromCode(json['role']?.toString());
    final defaultAvatar = role == UserRole.admin
        ? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100'
        : role == UserRole.parent
            ? 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100'
            : 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100';

    final customAvatar = json['profile_picture_url'] ?? json['profile_picture'] ?? json['avatar_url'];

    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? json['username'] ?? '',
      role: role,
      schoolId: schoolId,
      schoolName: schoolName,
      phoneNumber: json['phone_number'],
      avatarUrl: (customAvatar != null && customAvatar.toString().isNotEmpty)
          ? customAvatar.toString()
          : defaultAvatar,
    );
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    String? schoolId,
    String? schoolName,
    String? phoneNumber,
    String? avatarUrl,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      schoolId: schoolId ?? this.schoolId,
      schoolName: schoolName ?? this.schoolName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role.code,
      'school_id': schoolId,
      'school_name': schoolName,
      'phone_number': phoneNumber,
      'avatar_url': avatarUrl,
      'profile_picture_url': avatarUrl,
    };
  }
}
