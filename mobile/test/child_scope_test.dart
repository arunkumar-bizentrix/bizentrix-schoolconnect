import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/features/announcements/models/announcement_model.dart';
import 'package:school_connect/features/homework/models/homework_model.dart';
import 'package:school_connect/features/students/models/student_model.dart';
import 'package:school_connect/features/students/providers/child_scope.dart';

StudentModel _child({required int id, int? classId}) => StudentModel(
      id: id,
      admissionNumber: 'ADM00$id',
      firstName: 'Child',
      lastName: '$id',
      fullName: 'Child $id',
      classId: classId,
      className: 'Grade ${classId ?? 0} - A',
    );

HomeworkModel _homework({required int id, int? classId}) =>
    HomeworkModel.fromJson({
      'id': id,
      'classroom': classId,
      'classroom_name': 'Grade $classId - A',
      'subject': 'Mathematics',
      'title': 'Homework $id',
      'description': '',
      'due_date': '2026-09-15',
      'assigned_date': '2026-09-08',
    });

AnnouncementModel _notice({
  required int id,
  required String audience,
  int? targetClassId,
}) =>
    AnnouncementModel.fromJson({
      'id': id,
      'title': 'Notice $id',
      'content': 'Body',
      'priority': 'NORMAL',
      'audience_type': audience,
      'target_class': targetClassId,
      'published_at': '2026-09-08T09:00:00Z',
    });

void main() {
  group('ChildScope.homeworkFor', () {
    test('keeps only homework for the selected child class', () {
      final homework = [
        _homework(id: 1, classId: 10),
        _homework(id: 2, classId: 20),
        _homework(id: 3, classId: 10),
      ];

      final result = ChildScope.homeworkFor(homework, _child(id: 1, classId: 10));

      expect(result.map((h) => h.id), [1, 3]);
    });

    test('returns everything when no child is selected', () {
      final homework = [_homework(id: 1, classId: 10)];
      expect(ChildScope.homeworkFor(homework, null), hasLength(1));
    });

    test('returns everything when the child has no class yet', () {
      final homework = [_homework(id: 1, classId: 10)];
      final result = ChildScope.homeworkFor(homework, _child(id: 1));
      expect(result, hasLength(1));
    });
  });

  group('ChildScope.announcementsFor', () {
    test('keeps school-wide notices and the child own class notices', () {
      final notices = [
        _notice(id: 1, audience: 'SCHOOL'),
        _notice(id: 2, audience: 'CLASS', targetClassId: 10),
        _notice(id: 3, audience: 'CLASS', targetClassId: 20),
      ];

      final result =
          ChildScope.announcementsFor(notices, _child(id: 1, classId: 10));

      expect(result.map((n) => n.id), [1, 2]);
    });

    test('returns everything when no child is selected', () {
      final notices = [_notice(id: 1, audience: 'CLASS', targetClassId: 20)];
      expect(ChildScope.announcementsFor(notices, null), hasLength(1));
    });
  });
}
