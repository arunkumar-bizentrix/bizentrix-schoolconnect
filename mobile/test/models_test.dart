import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/features/announcements/models/announcement_model.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/homework/models/homework_model.dart';
import 'package:school_connect/features/notifications/models/notification_model.dart';
import 'package:school_connect/features/classes/models/class_model.dart';
import 'package:school_connect/features/students/models/student_model.dart';

/// Pure unit tests for JSON parsing of every API model.
/// No network, no platform channels - safe to run anywhere, including CI.
void main() {
  group('Models JSON Serialization & Role Mapping Tests', () {
    test('UserModel parses Django /api/v1/auth/me/ response correctly', () {
      final json = {
        'id': 1,
        'username': 'admin',
        'email': 'admin@greenwood.edu',
        'first_name': 'Greenwood',
        'last_name': 'Administrator',
        'role': 'ADMIN',
        'phone_number': '+919876543210',
        'school': {
          'id': 1,
          'name': 'Greenwood High International School',
          'code': 'GW001',
        },
      };

      final user = UserModel.fromJson(json);
      expect(user.id, '1');
      expect(user.email, 'admin@greenwood.edu');
      expect(user.role, UserRole.admin);
      expect(user.schoolId, '1');
      expect(user.schoolName, 'Greenwood High International School');
      expect(user.phoneNumber, '+919876543210');
      // No profile_picture_url in the payload: avatarUrl stays null and the
      // UI renders initials. It must never fall back to a stock photo.
      expect(user.avatarUrl, isNull);
      // No full_name in the payload, so the username is used for initials.
      expect(user.initials, 'A');
    });

    test('ClassModel parses teacher names and student count', () {
      final json = {
        'id': 10,
        'name': 'Grade 10',
        'section': 'A',
        'academic_year': '2025-2026',
        'is_active': true,
        'teacher_names': ['Priya Sharma', 'Vikram Malhotra'],
        'student_count': 35,
      };

      final cls = ClassModel.fromJson(json);
      expect(cls.id, 10);
      expect(cls.name, 'Grade 10');
      expect(cls.section, 'A');
      expect(cls.displayName, 'Grade 10 - A');
      expect(cls.academicYear, '2025-2026');
      expect(cls.teacherName, 'Priya Sharma, Vikram Malhotra');
      expect(cls.studentCount, 35);
    });

    test('StudentModel parses enrollment and admission fields', () {
      final json = {
        'id': 5,
        'first_name': 'Aarav',
        'last_name': 'Kumar',
        'admission_number': 'ADM001',
        'roll_number': '12',
        'class_enrolled': 1,
        'class_enrolled_name': 'Grade 5 - A',
        'academic_year': '2025-2026',
        'is_active': true,
      };

      final student = StudentModel.fromJson(json);
      expect(student.id, 5);
      expect(student.fullName, 'Aarav Kumar');
      expect(student.admissionNumber, 'ADM001');
      expect(student.className, 'Grade 5 - A');
      expect(student.academicYear, '2025-2026');
      expect(student.isActive, isTrue);
    });

    test('HomeworkModel parses classroom and due date', () {
      final json = {
        'id': 7,
        'classroom': 1,
        'classroom_name': 'Grade 5 - A',
        'subject': 'Mathematics',
        'title': 'Trigonometry Chapter 3',
        'description': 'Solve exercises 3.1 to 3.5',
        'due_date': '2026-09-15',
        'assigned_date': '2026-09-08',
        'academic_year': '2025-2026',
        'is_active': true,
      };

      final hw = HomeworkModel.fromJson(json);
      expect(hw.id, 7);
      expect(hw.subject, 'Mathematics');
      expect(hw.title, 'Trigonometry Chapter 3');
      expect(hw.className, 'Grade 5 - A');
      expect(hw.dueDate.year, 2026);
      expect(hw.academicYear, '2025-2026');
    });

    test('AnnouncementModel parses priority and audience types', () {
      final json = {
        'id': 3,
        'title': 'Annual Sports Day 2026',
        'content': 'All students must assemble in the sports ground at 8:00 AM.',
        'priority': 'URGENT',
        'audience_type': 'SCHOOL',
        'created_by_name': 'Greenwood Administrator',
        'published_at': '2026-09-08T09:00:00Z',
        'academic_year': '2025-2026',
      };

      final notice = AnnouncementModel.fromJson(json);
      expect(notice.id, 3);
      expect(notice.title, 'Annual Sports Day 2026');
      expect(notice.isUrgent, isTrue);
      expect(notice.audienceType, 'SCHOOL');
      expect(notice.audienceLabel, 'For All Students');
    });

    test('NotificationModel parses homework and announcement notifications correctly', () {
      final jsonHw = {
        'id': 101,
        'notification_type': 'HOMEWORK',
        'title': 'New Homework: Mathematics',
        'message': 'Exercise 4.2 has been assigned for Grade 10 - A.',
        'homework': 12,
        'announcement': null,
        'target_id': 12,
        'is_read': false,
        'created_at': '2026-09-10T14:30:00Z',
      };

      final notifHw = NotificationModel.fromJson(jsonHw);
      expect(notifHw.id, 101);
      expect(notifHw.isHomework, isTrue);
      expect(notifHw.isAnnouncement, isFalse);
      expect(notifHw.homeworkId, 12);
      expect(notifHw.isRead, isFalse);

      final readNotif = notifHw.copyWith(isRead: true);
      expect(readNotif.isRead, isTrue);

      final jsonNotice = {
        'id': 102,
        'notification_type': 'ANNOUNCEMENT',
        'title': 'School Circular: Sports Day',
        'message': 'Annual Sports meet on Friday.',
        'homework': null,
        'announcement': 5,
        'target_id': 5,
        'is_read': true,
        'created_at': '2026-09-10T15:00:00Z',
      };

      final notifNotice = NotificationModel.fromJson(jsonNotice);
      expect(notifNotice.id, 102);
      expect(notifNotice.isAnnouncement, isTrue);
      expect(notifNotice.isHomework, isFalse);
      expect(notifNotice.announcementId, 5);
      expect(notifNotice.isRead, isTrue);
    });

    test('UserModel uses the uploaded picture when the API provides one', () {
      final user = UserModel.fromJson({
        'id': 2,
        'username': 'priya',
        'full_name': 'Priya Sharma',
        'role': 'TEACHER',
        'profile_picture_url': 'http://localhost:8000/media/profile_pictures/p.png',
      });

      expect(user.avatarUrl, 'http://localhost:8000/media/profile_pictures/p.png');
      expect(user.initials, 'PS');
    });

    test('UserModel initials fall back safely for single and empty names', () {
      UserModel build(String fullName) => UserModel.fromJson({
            'id': 3,
            'username': 'u',
            'full_name': fullName,
            'role': 'PARENT',
          });

      expect(build('Ravi').initials, 'R');
      // Blank full_name falls back to the username ('u').
      expect(build('  ').initials, 'U');
    });
  });

}
