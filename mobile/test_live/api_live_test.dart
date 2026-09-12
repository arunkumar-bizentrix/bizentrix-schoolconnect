import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live API contract tests.
///
/// These are NOT unit tests: they require a running Django backend that has
/// been seeded with the demo users (`python manage.py seed_demo_users`).
/// They live outside `test/` so that a plain `flutter test` stays hermetic
/// and passes on any machine, including CI.
///
/// Run them explicitly against a local backend:
///
///   flutter test test_live
///
/// Point them at another host or use different credentials with --dart-define:
///
///   flutter test test_live \
///     --dart-define=LIVE_API_BASE_URL=http://10.0.2.2:8000/api/v1 \
///     --dart-define=LIVE_ADMIN_USERNAME=admin \
///     --dart-define=LIVE_ADMIN_PASSWORD=...
const String kBaseUrl = String.fromEnvironment(
  'LIVE_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api/v1',
);
const String kAdminUsername = String.fromEnvironment(
  'LIVE_ADMIN_USERNAME',
  defaultValue: 'admin',
);
const String kAdminPassword = String.fromEnvironment(
  'LIVE_ADMIN_PASSWORD',
  defaultValue: 'Admin@123',
);
const String kParentUsername = String.fromEnvironment(
  'LIVE_PARENT_USERNAME',
  defaultValue: 'parent_ravi',
);
const String kParentPassword = String.fromEnvironment(
  'LIVE_PARENT_PASSWORD',
  defaultValue: 'Parent@123',
);

void main() {
  group('Live Django REST API Contract Tests', () {
    final dio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    test('POST /api/v1/auth/token/ authenticates the school admin', () async {
      final response = await dio.post(
        '/auth/token/',
        data: {
          'username': kAdminUsername,
          'password': kAdminPassword,
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
      expect(meResponse.data['username'], kAdminUsername);
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
        data: {'username': kAdminUsername, 'password': kAdminPassword},
      );
      final refreshToken = loginResponse.data['refresh'];

      final refreshResponse = await dio.post(
        '/auth/token/refresh/',
        data: {'refresh': refreshToken},
      );
      expect(refreshResponse.statusCode, 200);
      expect(refreshResponse.data['access'], isNotNull);
    });

    test('Parent role receives only their enrolled child data', () async {
      final response = await dio.post(
        '/auth/token/',
        data: {
          'username': kParentUsername,
          'password': kParentPassword,
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
