/// A subject the school teaches. Timetable periods and, later, marks point at
/// one of these rather than repeating a free-text name.
class SubjectModel {
  const SubjectModel({
    required this.id,
    required this.name,
    this.code = '',
    this.isActive = true,
  });

  final int id;
  final String name;
  final String code;
  final bool isActive;

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      isActive: json['is_active'] != false,
    );
  }
}
