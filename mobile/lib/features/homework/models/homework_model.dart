import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Parses the API's "HH:MM:SS" time string. Null when the teacher set no time.
TimeOfDay? _parseTime(dynamic raw) {
  if (raw == null) return null;
  final parts = raw.toString().split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

class HomeworkModel {
  final int id;
  final int? classId;
  final String className;
  final int? studentId;
  final String? studentName;
  final String subject;
  final String title;
  final String description;
  final String assignedByName;
  final DateTime assignedDate;
  final DateTime dueDate;

  /// Optional clock deadline on the due date. Null means "due that day",
  /// which is how homework worked before the field existed.
  final TimeOfDay? dueTime;

  /// Server-formatted deadline, e.g. "17 Sep 2026, 4:00 PM".
  final String dueDisplay;
  /// The backend's permission-checked download route - not a public link.
  final String? attachmentUrl;
  final String? attachmentName;
  final String academicYear;
  final bool isActive;

  const HomeworkModel({
    required this.id,
    this.classId,
    required this.className,
    this.studentId,
    this.studentName,
    required this.subject,
    required this.title,
    required this.description,
    this.assignedByName = 'Faculty',
    required this.assignedDate,
    required this.dueDate,
    this.dueTime,
    this.dueDisplay = '',
    this.attachmentUrl,
    this.attachmentName,
    this.academicYear = AppConstants.currentAcademicYear,
    this.isActive = true,
  });

  /// The exact moment the homework is due: end of the due date unless the
  /// teacher set a time.
  DateTime get dueAt {
    final time = dueTime;
    if (time == null) {
      return DateTime(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59);
    }
    return DateTime(
        dueDate.year, dueDate.month, dueDate.day, time.hour, time.minute);
  }

  bool get isOverdue => dueAt.isBefore(DateTime.now());

  factory HomeworkModel.fromJson(Map<String, dynamic> json) {
    int? cId;
    if (json['classroom'] is int) {
      cId = json['classroom'];
    } else if (json['classroom'] is Map) {
      cId = json['classroom']['id'];
    } else if (json['classroom'] != null) {
      cId = int.tryParse(json['classroom'].toString());
    }

    int? sId;
    if (json['student'] is int) {
      sId = json['student'];
    } else if (json['student'] is Map) {
      sId = json['student']['id'];
    } else if (json['student'] != null) {
      sId = int.tryParse(json['student'].toString());
    }

    return HomeworkModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      classId: cId,
      className: json['classroom_name'] ?? 'Class',
      studentId: sId,
      studentName: json['student_name'],
      subject: json['subject'] ?? 'General',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      assignedByName: json['assigned_by_name'] ?? 'Faculty',
      assignedDate: DateTime.tryParse(json['assigned_date'] ?? '') ?? DateTime.now(),
      dueDate: DateTime.tryParse(json['due_date'] ?? '') ?? DateTime.now().add(const Duration(days: 2)),
      dueTime: _parseTime(json['due_time']),
      dueDisplay: (json['due_display'] ?? '').toString(),
      attachmentUrl: json['attachment_url']?.toString(),
      attachmentName: json['attachment_name']?.toString(),
      academicYear: json['academic_year'] ?? AppConstants.currentAcademicYear,
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'classroom': classId,
      'classroom_name': className,
      'subject': subject,
      'title': title,
      'description': description,
      'assigned_date': assignedDate.toIso8601String().split('T').first,
      'due_date': dueDate.toIso8601String().split('T').first,
      if (dueTime != null)
        'due_time':
            '${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}',
      'attachment_url': attachmentUrl,
      'attachment_name': attachmentName,
      'is_active': isActive,
    };
  }
}
