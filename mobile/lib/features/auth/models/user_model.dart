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
    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? json['username'] ?? '',
      role: UserRole.fromCode(json['role']),
      schoolId: json['school_id']?.toString(),
      schoolName: json['school_name'],
      phoneNumber: json['phone_number'],
      avatarUrl: json['avatar_url'],
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
    };
  }
}
