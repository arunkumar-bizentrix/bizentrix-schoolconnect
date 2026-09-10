
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/school/models/class_model.dart';
import 'package:school_connect/features/school/models/student_model.dart';
import 'package:school_connect/features/homework/models/homework_model.dart';
import 'package:school_connect/features/announcements/models/announcement_model.dart';
import 'package:school_connect/features/notifications/models/notification_model.dart';

void main() {
  group('1. Models JSON Serialization & Role Mapping Tests', () {
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
      expect(user.avatarUrl, isNotEmpty);
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
      expect(hw.classroomName, 'Grade 5 - A');
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
  });

  group('2. TokenStorage Persistence Tests', () {
    test('Saves, retrieves, and clears tokens and profile', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = TokenStorage(const FlutterSecureStorage());

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.hasValidSession(), isFalse);

      await storage.saveTokens(
        accessToken: 'mock_access_jwt',
        refreshToken: 'mock_refresh_jwt',
      );

      expect(await storage.getAccessToken(), 'mock_access_jwt');
      expect(await storage.getRefreshToken(), 'mock_refresh_jwt');
      expect(await storage.hasValidSession(), isTrue);

      final profileJson = jsonEncode({'id': '1', 'name': 'Admin User'});
      await storage.saveUserProfileJson(profileJson);
      expect(await storage.getUserProfileJson(), profileJson);

      await storage.saveBaseUrlOverride('http://192.168.1.50:8000/api/v1');
      expect(await storage.getBaseUrlOverride(), 'http://192.168.1.50:8000/api/v1');

      await storage.clearAll();
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getUserProfileJson(), isNull);
      expect(await storage.hasValidSession(), isFalse);
    });
  });

  group('3. Live Django REST API Integration Tests', () {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    test('POST /api/v1/auth/token/ authenticates School A Admin', () async {
      final response = await dio.post(
        '/auth/token/',
        data: {
          'username': 'admin',
          'password': 'Admin@123',
        },
      );

      expect(response.statusCode, 200);
      expect(response.data['access'], isNotNull);
      expect(response.data['refresh'], isNotNull);

      final accessToken = response.data['access'];

      // Verify GET /api/v1/auth/me/
      final meResponse = await dio.get(
        '/auth/me/',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      expect(meResponse.statusCode, 200);
      expect(meResponse.data['username'], 'admin');
      expect(meResponse.data['role'], 'ADMIN');
      expect(meResponse.data['school']['name'], contains('Vivekananda'));

      // Verify GET /api/v1/classes/
      final classesResponse = await dio.get(
        '/classes/',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      expect(classesResponse.statusCode, 200);
      final classes = classesResponse.data is List
          ? classesResponse.data as List
          : classesResponse.data['results'] as List;
      expect(classes, isNotEmpty);

      // Verify GET /api/v1/students/
      final studentsResponse = await dio.get(
        '/students/',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      expect(studentsResponse.statusCode, 200);
      final students = studentsResponse.data is List
          ? studentsResponse.data as List
          : studentsResponse.data['results'] as List;
      expect(students, isNotEmpty);

      // Verify GET /api/v1/homework/
      final homeworkResponse = await dio.get(
        '/homework/',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      expect(homeworkResponse.statusCode, 200);

      // Verify GET /api/v1/announcements/
      final announcementsResponse = await dio.get(
        '/announcements/',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      expect(announcementsResponse.statusCode, 200);
    });

    test('POST /api/v1/auth/token/refresh/ rotates access token', () async {
      final loginResponse = await dio.post(
        '/auth/token/',
        data: {'username': 'admin', 'password': 'Admin@123'},
      );
      final refreshToken = loginResponse.data['refresh'];

      final refreshResponse = await dio.post(
        '/auth/token/refresh/',
        data: {'refresh': refreshToken},
      );
      expect(refreshResponse.statusCode, 200);
      expect(refreshResponse.data['access'], isNotNull);
    });

    test('School B User is strictly isolated to School B data', () async {
      final response = await dio.post(
        '/auth/token/',
        data: {
          'username': 'admin_xyz',
          'password': 'Admin@123',
        },
      );
      expect(response.statusCode, 200);
      final token = response.data['access'];

      final me = await dio.get(
        '/auth/me/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      expect(me.data['school']['name'], contains('XYZ International'));

      final classesResponse = await dio.get(
        '/classes/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final classes = classesResponse.data is List
          ? classesResponse.data as List
          : classesResponse.data['results'] as List;

      // School B has its own classes, distinct from School A
      for (final c in classes) {
        expect(c['name'], isNot(contains('Greenwood')));
      }
    });

    test('Parent role Ravi receives his enrolled child data', () async {
      final response = await dio.post(
        '/auth/token/',
        data: {
          'username': 'parent_ravi',
          'password': 'Parent@123',
        },
      );
      expect(response.statusCode, 200);
      final token = response.data['access'];

      final studentsResponse = await dio.get(
        '/students/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final students = studentsResponse.data is List
          ? studentsResponse.data as List
          : studentsResponse.data['results'] as List;

      // Ravi has child Aarav Kumar
      expect(students.any((s) => s['admission_number'] == 'ADM001'), isTrue);
    });

    test('POST /api/v1/auth/otp/send/ dispatches via Meta WhatsApp Cloud API or Dev Service', () async {
      try {
        final response = await dio.post(
          '/auth/otp/send/',
          data: {'phone_number': '9876543210'},
        );
        expect(response.statusCode, 200);
        expect(response.data['success'], isTrue);
        expect(response.data['message'], contains('WhatsApp'));
      } on DioException catch (e) {
        // In Live Meta Cloud API mode with a test sandbox, numbers outside the verified recipient list return 400
        expect(e.response?.statusCode, 400);
        expect(e.response?.data.toString(), anyOf(
          contains('allowed list'),
          contains('WhatsApp delivery failed'),
          contains('Please wait'),
          contains('not registered with a school'),
        ));
      }
    });

    test('POST /api/v1/auth/otp/verify/ with invalid OTP returns 400 error', () async {
      try {
        await dio.post(
          '/auth/otp/verify/',
          data: {
            'phone_number': '9876543210',
            'otp': '000000',
          },
        );
        fail('Expected DioException with 400');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 400);
        expect(e.response?.data.toString(), anyOf(
          contains('attempt(s) remaining'),
          contains('No active OTP request found'),
          contains('Invalid OTP code'),
          contains('expired'),
        ));
      }
    });

    test('POST /api/v1/auth/otp/send/ rejects unregistered phone number', () async {
      try {
        await dio.post(
          '/auth/otp/send/',
          data: {'phone_number': '9999999999'},
        );
        fail('Expected DioException with 400');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 400);
        expect(e.response?.data.toString(), contains('not registered with a school'));
      }
    });

    test('POST /api/v1/auth/otp/email/send/ returns anti-enumeration generic 200 response', () async {
      final testEmail = 'unregistered_${DateTime.now().millisecondsSinceEpoch}@example.com';
      final response = await dio.post(
        '/auth/otp/email/send/',
        data: {'email': testEmail},
      );
      expect(response.statusCode, 200);
      expect(response.data['success'], isTrue);
      expect(response.data['status'], 'success');
      expect(response.data['message'], contains('OTP has been sent'));
      expect(response.data['expires_in_seconds'], 300);
      expect(response.data.containsKey('otp'), isFalse);
      expect(response.data.containsKey('otp_debug'), isFalse);
    });

    test('POST /api/v1/auth/otp/email/verify/ with invalid OTP returns 400', () async {
      try {
        await dio.post(
          '/auth/otp/email/verify/',
          data: {
            'email': 'priya.teacher@abcmatric.edu',
            'otp': '000000',
          },
        );
        fail('Expected DioException with 400');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 400);
        expect(e.response?.data.toString(), anyOf(
          contains('Invalid verification code'),
          contains('No active OTP request found'),
          contains('expired'),
        ));
      }
    });
  });
}

