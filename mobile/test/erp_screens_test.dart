import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';
import 'package:school_connect/features/exams/models/exam_models.dart';
import 'package:school_connect/features/exams/screens/class_results_screen.dart';
import 'package:school_connect/features/exams/screens/create_exam_screen.dart';
import 'package:school_connect/features/exams/screens/exam_detail_screen.dart';
import 'package:school_connect/features/exams/screens/exams_screen.dart';
import 'package:school_connect/features/exams/screens/mark_entry_screen.dart';
import 'package:school_connect/features/exams/screens/report_card_screen.dart';
import 'package:school_connect/features/people/screens/people_screen.dart';
import 'package:school_connect/features/students/models/child_today.dart';
import 'package:school_connect/features/students/screens/child_today_card.dart';

/// The exam, people and Today screens with realistic - and deliberately long -
/// data, at the narrow widths real phones have. Empty lists never overflow;
/// "Aishwarya Lakshmi Narayanan" in "Environmental Science" does.

const _longName = 'Aishwarya Lakshmi Narayanan Subramaniam';

final Map<String, Object> _responses = {
  '/auth/staff/': {
    'count': 2,
    'next': null,
    'previous': null,
    'results': [
      {
        'id': 1,
        'username': 'aishwarya',
        'full_name': _longName,
        'email': 'aishwarya.lakshmi.narayanan@vivekananda.school',
        'phone_number': '9876543210',
        'role': 'TEACHER',
        'is_active': true,
        'linked': ['Grade 10 - A', 'Grade 10 - B', 'Grade 9 - C', 'Grade 8 - D', 'Grade 7 - E'],
      },
      {
        'id': 2,
        'username': 'ravi',
        'full_name': 'Ravi',
        'email': '',
        'phone_number': '9123456780',
        'role': 'TEACHER',
        'is_active': false,
        'linked': [],
      },
    ],
  },
  '/exams/': {
    'count': 1,
    'next': null,
    'previous': null,
    'results': [_exam],
  },
  '/exams/7/': _exam,
  '/exams/7/papers/': [
    for (final (index, subject) in ['Mathematics', 'Environmental Science', 'Tamil', 'English Literature'].indexed)
      {
        'id': 100 + index,
        'exam': 7,
        'classroom': 3,
        'classroom_name': 'Grade 10 - A',
        'subject': index,
        'subject_name': subject,
        'max_marks': 100,
        'pass_marks': 35,
        'exam_date': null,
        'entered_count': 38,
        'can_enter_marks': index.isEven,
      },
    {
      'id': 200,
      'exam': 7,
      'classroom': 4,
      'classroom_name': 'Grade 10 - B',
      'subject': 0,
      'subject_name': 'Mathematics',
      'max_marks': 100,
      'pass_marks': 35,
      'entered_count': 0,
      'can_enter_marks': false,
    },
  ],
  '/exam-papers/100/marks/': {
    'paper': {
      'id': 100,
      'exam': 7,
      'classroom': 3,
      'classroom_name': 'Grade 10 - A',
      'subject': 0,
      'subject_name': 'Environmental Science',
      'max_marks': 100,
      'pass_marks': 35,
      'can_enter_marks': true,
    },
    'exam_name': 'Quarterly Examination 2026',
    'is_published': false,
    'students': [
      {'student': 1, 'student_name': _longName, 'admission_number': 'VSB-2026-000123', 'marks_obtained': 98.5, 'is_absent': false},
      {'student': 2, 'student_name': 'Rahul', 'admission_number': 'VSB-2', 'marks_obtained': null, 'is_absent': true},
      {'student': 3, 'student_name': 'Kavya', 'admission_number': 'VSB-3', 'marks_obtained': 20, 'is_absent': false},
    ],
  },
  '/exams/7/results/': {
    'exam': 7,
    'exam_name': 'Quarterly Examination 2026',
    'is_published': false,
    'classroom': 3,
    'classroom_name': 'Grade 10 - A',
    'max_total': 600,
    'ranked_count': 38,
    'papers': [
      for (final subject in _subjects) {'id': 1, 'subject': subject, 'max_marks': 100, 'pass_marks': 35},
    ],
    'rows': [_resultRow(rank: 1, result: 'PASS'), _resultRow(rank: null, result: 'INCOMPLETE')],
  },
  '/report-card/': {
    'student': 1,
    'student_name': _longName,
    'admission_number': 'VSB-2026-000123',
    'classroom_name': 'Grade 10 - A',
    'exams': [
      {
        ..._resultRow(rank: 12, result: 'FAIL'),
        'exam': 7,
        'exam_name': 'Quarterly Examination 2026 (Revised Schedule)',
        'academic_year': '2026-2027',
        'classroom_name': 'Grade 10 - A',
        'is_published': false,
        'class_size': 38,
      },
    ],
  },
  '/classes/': {
    'count': 1,
    'next': null,
    'previous': null,
    'results': [
      {'id': 3, 'name': 'Grade 10', 'section': 'A', 'academic_year': '2026-2027', 'display_name': 'Grade 10 - A (2026-2027)'},
    ],
  },
  '/subjects/': [
    for (final (index, subject) in _subjects.indexed) {'id': index + 1, 'name': subject, 'is_active': true},
  ],
};

const _subjects = ['Mathematics', 'Environmental Science', 'Tamil', 'English Literature', 'Social Science', 'Computer Applications'];

const _exam = {
  'id': 7,
  'name': 'Quarterly Examination 2026 (Revised Schedule)',
  'academic_year': '2026-2027',
  'start_date': '2026-09-20',
  'end_date': '2026-10-02',
  'is_published': false,
  'classrooms': [
    {'id': 3, 'name': 'Grade 10 - A'},
    {'id': 4, 'name': 'Grade 10 - B'},
  ],
  'subjects': _subjects,
  'paper_count': 12,
};

Map<String, Object?> _resultRow({required int? rank, required String result}) => {
      'student': 1,
      'student_name': _longName,
      'admission_number': 'VSB-2026-000123',
      'subjects': [
        for (final subject in _subjects)
          {
            'paper': 1,
            'subject': subject,
            'max_marks': 100,
            'pass_marks': 35,
            'marks_obtained': subject == 'Tamil' ? 12.5 : 99.5,
            'is_absent': false,
            'entered': true,
            'passed': subject != 'Tamil',
          },
      ],
      'total': 510.0,
      'max_total': 600,
      'percentage': 85.0,
      'result': result,
      'rank': rank,
    };

class _RoutedAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = _responses[options.path] ?? {'count': 0, 'next': null, 'previous': null, 'results': []};
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(ApiClient client, TokenStorage storage, UserRole role)
      : super(apiClient: client, tokenStorage: storage) {
    state = AuthState(
      user: UserModel(id: '1', email: 'admin@example.test', fullName: 'School Admin', role: role),
    );
  }

  @override
  Future<bool> restoreSession() async => true;
}

Widget _wrap(Widget screen, UserRole role) {
  final storage = TokenStorage(const FlutterSecureStorage());
  final client = ApiClient(tokenStorage: storage);
  client.dio.httpClientAdapter = _RoutedAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((ref) => _TestAuthNotifier(client, storage, role)),
    ],
    child: MaterialApp(home: screen),
  );
}

final _today = ChildToday.fromJson({
  'student': 1,
  'student_name': _longName,
  'classroom': 3,
  'classroom_name': 'Grade 10 - A',
  'class_teacher_name': 'Priya Sharma',
  'attendance': {'status': 'PRESENT', 'note': 'Reached at 8:55 after the school bus broke down', 'percentage': 92.3, 'days_recorded': 40},
  'periods': [
    for (final (index, subject) in _subjects.indexed)
      {
        'period': index + 1,
        'subject_name': subject,
        'teacher_name': _longName,
        'start_time': '${(9 + index).toString().padLeft(2, '0')}:00:00',
        'end_time': '${(9 + index).toString().padLeft(2, '0')}:45:00',
        'time_display': '',
      },
  ],
  'homework_today': [
    for (var i = 0; i < 5; i++)
      {'id': i, 'title': 'Complete the long answer questions from chapter $i and draw the diagrams', 'subject': 'Environmental Science', 'due_display': '15 Sep 2026, 4:00 PM', 'due_today': i == 0},
  ],
  'homework_due_soon': [
    {'id': 9, 'title': 'Essay', 'subject': 'English Literature', 'due_display': '17 Sep 2026, 9:00 AM'},
  ],
  'latest_result': {'exam': 7, 'exam_name': 'Quarterly Examination 2026 (Revised Schedule)', 'total': 510.5, 'max_total': 600, 'percentage': 85.1, 'rank': 12, 'class_size': 38, 'result': 'PASS'},
});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> pumpAt(WidgetTester tester, Widget screen, double width, {UserRole role = UserRole.admin}) async {
    tester.view.physicalSize = Size(width * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(screen, role));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  final screens = <String, Widget>{
    'PeopleScreen': const PeopleScreen(),
    'ExamsScreen': const ExamsScreen(),
    'CreateExamScreen': const CreateExamScreen(),
    'ExamDetailScreen': const ExamDetailScreen(examId: 7, title: 'Quarterly'),
    'MarkEntryScreen': const MarkEntryScreen(paperId: 100, examId: 7),
    'ClassResultsScreen': const ClassResultsScreen(examId: 7, classId: 3),
    'ReportCardScreen': const ReportCardScreen(studentId: 1),
    'ChildTodayCard': Scaffold(body: SingleChildScrollView(child: ChildTodayCard(today: _today, now: DateTime(2026, 9, 14, 10, 20)))),
  };

  for (final width in [320.0, 360.0, 430.0]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} fits ${width.toInt()}dp with long real-world data', (tester) async {
        await pumpAt(tester, entry.value, width);
        expect(tester.takeException(), isNull, reason: '${entry.key} overflowed at ${width}dp');
      });
    }
  }

  testWidgets('people list shows a teacher\'s classes and flags a deactivated one', (tester) async {
    await pumpAt(tester, const PeopleScreen(), 430);
    expect(find.text(_longName), findsOneWidget);
    expect(find.text('Grade 10 - A'), findsOneWidget);
    expect(find.text('+1 more'), findsOneWidget);
    expect(find.text('Deactivated'), findsOneWidget);
  });

  testWidgets('teacher sees Enter marks only on the subject they teach', (tester) async {
    await pumpAt(tester, const ExamDetailScreen(examId: 7, title: 'Quarterly'), 430, role: UserRole.teacher);
    expect(find.text('Enter marks'), findsNWidgets(2));
    expect(find.text('View'), findsNWidgets(2));
    expect(find.text('Publish results to parents'), findsNothing);
  });

  testWidgets('admin gets the publish button', (tester) async {
    await pumpAt(tester, const ExamDetailScreen(examId: 7, title: 'Quarterly'), 430);
    expect(find.text('Publish results to parents'), findsOneWidget);
  });

  testWidgets('mark entry flags marks above the maximum before saving', (tester) async {
    await pumpAt(tester, const MarkEntryScreen(paperId: 100, examId: 7), 430, role: UserRole.teacher);
    expect(find.text('All changes saved'), findsOneWidget);
    expect(find.text('Below pass mark'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '140');
    await tester.pump();
    expect(find.text('Max 100'), findsOneWidget);
    expect(find.text('Save marks'), findsOneWidget);
  });

  testWidgets('Today card names the period running now', (tester) async {
    await pumpAt(tester, screens['ChildTodayCard']!, 430);
    expect(find.textContaining('Now: Environmental Science'), findsOneWidget);
    expect(find.textContaining('reached school'), findsOneWidget);
    expect(find.text('+2 more in Homework'), findsOneWidget);
    expect(find.text('12th'), findsOneWidget);
  });

  group('exam model helpers', () {
    test('ordinal ranks', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111].map(ordinal).toList(),
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '101st', '111th']);
    });

    test('marks drop a trailing .0 but keep halves', () {
      expect(formatMarks(88.0), '88');
      expect(formatMarks(65.5), '65.5');
      expect(formatMarks(null), '-');
    });

    test('an absent subject reads AB and a missing one reads -', () {
      expect(SubjectMark.fromJson({'subject': 'Tamil', 'entered': true, 'is_absent': true}).display, 'AB');
      expect(SubjectMark.fromJson({'subject': 'Tamil', 'entered': false}).display, '-');
    });

    test('results parse outcomes and unranked rows', () {
      final row = ResultRow.fromJson(_resultRow(rank: null, result: 'INCOMPLETE'));
      expect(row.rank, isNull);
      expect(row.outcome, ExamOutcome.incomplete);
      expect(row.subjects, hasLength(_subjects.length));
    });

    test('a period without times is never "now"', () {
      const period = TodayPeriod(period: 1, subjectName: 'Tamil');
      expect(period.isRunningAt(DateTime(2026, 9, 14, 10)), isFalse);
    });
  });
}

