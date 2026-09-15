"""
Totals, ranks, results and report cards.

Nothing here is stored: a total or a rank saved in a column goes stale the
moment one mark is corrected. Everything is computed from Mark rows, with a
fixed number of queries per class.
"""

import logging
from collections import defaultdict
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.notifications.models import Notification
from apps.students.models import Student
from apps.timetable.models import TimetableSlot

from .grading import bands_for_school, grade_for
from .models import ExamPaper, Mark

logger = logging.getLogger('schoolconnect.exams')

PASS = 'PASS'
FAIL = 'FAIL'
INCOMPLETE = 'INCOMPLETE'


class ExamError(ValueError):
    """A request that cannot be honoured, with a message fit for the admin."""


# ---------------------------------------------------------------------------
# who may enter marks
# ---------------------------------------------------------------------------

def can_enter_marks(user, paper):
    """
    The teacher who teaches the subject to that class enters its marks.

    "Who teaches it" comes from the timetable, so the school records it once.
    The class teacher may always enter marks for their class (covering an
    absent colleague), and so may the admin. A school that has not built its
    timetable yet is not locked out: with no period of that subject scheduled,
    any teacher assigned to the class may enter it.
    """
    if user.is_superuser or user.role == 'ADMIN':
        return True
    if user.role != 'TEACHER':
        return False

    classroom = paper.classroom
    if classroom.class_teacher_id == user.id:
        return True

    slots = TimetableSlot.objects.filter(classroom=classroom, subject=paper.subject)
    if slots.filter(teacher=user).exists():
        return True
    if not slots.exclude(teacher__isnull=True).exists():
        return classroom.teachers.filter(id=user.id).exists()
    return False


# ---------------------------------------------------------------------------
# results
# ---------------------------------------------------------------------------

def _one_decimal(value):
    return float(Decimal(value).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP))


def compute_class_results(exam, classroom, papers=None, bands=None):
    """
    Every student's result for one class in one exam, best first.

    Returns ``{'papers': [...], 'max_total': n, 'rows': [...]}``. Each row has
    per-subject marks and grades, total, percentage, overall grade, result and
    rank. Grades never influence the rank, which is by total marks alone.

    Rank uses standard competition ranking - two students on 450 are both 2nd
    and the next is 4th, which is how Indian schools announce it. Only
    students with every paper entered are ranked; a missing mark would
    otherwise push a strong student to the bottom.
    """
    if papers is None:
        papers = list(
            ExamPaper.objects.filter(exam=exam, classroom=classroom).select_related('subject')
        )
    if bands is None:
        bands = bands_for_school(exam.school_id)
    paper_ids = [paper.id for paper in papers]
    max_total = sum(paper.max_marks for paper in papers)

    marks_by_student = defaultdict(dict)
    for mark in Mark.objects.filter(paper_id__in=paper_ids):
        marks_by_student[mark.student_id][mark.paper_id] = mark

    # The class's students this year, plus anyone who has marks here but has
    # since moved class - a past exam must keep its whole cohort.
    students = Student.objects.filter(
        Q(id__in=set(marks_by_student)) | Q(class_enrolled=classroom, is_active=True)
    ).order_by('first_name', 'last_name')

    rows = []
    for student in students:
        entered = marks_by_student.get(student.id, {})
        subjects = []
        total = Decimal('0')
        failed = False
        for paper in papers:
            mark = entered.get(paper.id)
            if mark is None:
                subjects.append({
                    'paper': paper.id,
                    'subject': paper.subject.name,
                    'max_marks': paper.max_marks,
                    'pass_marks': paper.pass_marks,
                    'marks_obtained': None,
                    'percentage': None,
                    'grade': None,
                    'is_absent': False,
                    'entered': False,
                    'passed': None,
                })
                continue

            obtained = mark.marks_obtained if not mark.is_absent else None
            passed = (
                not mark.is_absent
                and obtained is not None
                and obtained >= paper.pass_marks
            )
            failed = failed or not passed
            total += obtained or 0
            # Each subject is graded on its own percentage, so a practical
            # out of 50 is graded like a theory paper out of 100.
            subject_percentage = (
                _one_decimal(obtained * 100 / paper.max_marks)
                if obtained is not None and paper.max_marks else None
            )
            subjects.append({
                'paper': paper.id,
                'subject': paper.subject.name,
                'max_marks': paper.max_marks,
                'pass_marks': paper.pass_marks,
                'marks_obtained': float(obtained) if obtained is not None else None,
                'percentage': subject_percentage,
                'grade': grade_for(subject_percentage, bands),
                'is_absent': mark.is_absent,
                'entered': True,
                'passed': passed,
            })

        complete = bool(papers) and len(entered) >= len(papers)
        if not complete:
            result = INCOMPLETE
        else:
            result = FAIL if failed else PASS

        percentage = _one_decimal(total * 100 / max_total) if max_total else 0.0
        rows.append({
            'student': student.id,
            'student_name': student.full_name,
            'admission_number': student.admission_number,
            'subjects': subjects,
            'total': _one_decimal(total),
            'max_total': max_total,
            'percentage': percentage,
            # No overall grade until every paper is in - a partial total would
            # grade the student on the subjects that happen to be entered.
            'grade': grade_for(percentage, bands) if complete else None,
            'result': result,
            'rank': None,
            'is_complete': complete,
        })

    ranked = sorted(
        (row for row in rows if row['is_complete']),
        key=lambda row: row['total'],
        reverse=True,
    )
    previous_total, previous_rank = None, 0
    for position, row in enumerate(ranked, start=1):
        if row['total'] != previous_total:
            previous_rank, previous_total = position, row['total']
        row['rank'] = previous_rank

    rows.sort(key=lambda row: (row['rank'] is None, row['rank'] or 0, row['student_name']))
    return {
        'papers': papers,
        'max_total': max_total,
        'ranked_count': len(ranked),
        'rows': rows,
    }


def missing_marks(exam):
    """How many (student, paper) marks are still not entered, per class."""
    missing = {}
    papers_by_class = defaultdict(list)
    for paper in exam.papers.select_related('classroom', 'subject'):
        papers_by_class[paper.classroom].append(paper)

    bands = bands_for_school(exam.school_id)
    for classroom, papers in papers_by_class.items():
        rows = compute_class_results(exam, classroom, papers, bands)['rows']
        count = sum(
            1 for row in rows for subject in row['subjects'] if not subject['entered']
        )
        if count:
            missing[str(classroom)] = count
    return missing


# ---------------------------------------------------------------------------
# publishing
# ---------------------------------------------------------------------------

@transaction.atomic
def publish_exam(exam, *, allow_incomplete=False):
    """
    Makes results visible to parents and tells them.

    Refuses while marks are missing unless the admin explicitly accepts that -
    publishing a half-entered exam hands parents a wrong total and rank.
    Returns the number of parent notifications created.
    """
    if exam.is_published:
        raise ExamError('These results are already published.')
    if not exam.papers.exists():
        raise ExamError('This exam has no subjects yet, so there is nothing to publish.')

    missing = missing_marks(exam)
    if missing and not allow_incomplete:
        total = sum(missing.values())
        classes = ', '.join(f'{name} ({count})' for name, count in missing.items())
        raise ExamError(
            f'{total} marks are still not entered: {classes}. '
            'Enter them, mark the student absent, or publish anyway.'
        )

    exam.is_published = True
    exam.published_at = timezone.now()
    exam.save(update_fields=['is_published', 'published_at', 'updated_at'])

    return notify_results(exam)


def unpublish_exam(exam):
    """Hides results again so a mistake can be corrected."""
    exam.is_published = False
    exam.published_at = None
    exam.save(update_fields=['is_published', 'published_at', 'updated_at'])


def notify_results(exam):
    """One notification per parent per child, carrying that child's own result."""
    from apps.notifications.services import NotificationService

    try:
        notifications = []
        papers_by_class = defaultdict(list)
        for paper in exam.papers.select_related('classroom', 'subject'):
            papers_by_class[paper.classroom].append(paper)

        bands = bands_for_school(exam.school_id)
        for classroom, papers in papers_by_class.items():
            results = compute_class_results(exam, classroom, papers, bands)
            students = {
                student.id: student
                for student in Student.objects.filter(
                    id__in=[row['student'] for row in results['rows']]
                ).prefetch_related('parents')
            }
            for row in results['rows']:
                student = students.get(row['student'])
                if student is None:
                    continue
                first_name = student.first_name or student.full_name
                summary = f"{first_name} scored {row['total']:g}/{row['max_total']} ({row['percentage']:g}%)"
                if row['grade']:
                    summary += f" · Grade {row['grade']}"
                if row['rank']:
                    summary += f" · Rank {row['rank']} of {results['ranked_count']}"
                summary += '.'

                for parent in student.parents.all():
                    if not parent.is_active:
                        continue
                    notifications.append(Notification(
                        recipient=parent,
                        notification_type=Notification.NotificationType.RESULT,
                        title=f'{exam.name} results are out',
                        message=summary,
                        exam=exam,
                        student=student,
                    ))

        if not notifications:
            return 0
        created = Notification.objects.bulk_create(notifications)
        NotificationService._push(created)
        logger.info('Created %d result notifications for exam %s', len(created), exam.pk)
        return len(created)
    except Exception as exc:
        # Results are published either way; a failed alert must not undo that.
        logger.error('Failed to notify results for exam %s: %s', exam.pk, exc)
        return 0


# ---------------------------------------------------------------------------
# report card
# ---------------------------------------------------------------------------

def report_card(student, *, published_only):
    """
    A student's marksheet across exams, newest first.

    Exams come from the student's own marks and from their current class, so
    last year's results survive promotion into a new class.
    """
    paper_ids = set(Mark.objects.filter(student=student).values_list('paper_id', flat=True))
    if student.class_enrolled_id:
        paper_ids |= set(
            ExamPaper.objects.filter(classroom_id=student.class_enrolled_id)
            .values_list('id', flat=True)
        )

    papers = (
        ExamPaper.objects.filter(id__in=paper_ids)
        .select_related('exam', 'classroom', 'subject')
        .order_by('-exam__start_date', '-exam__created_at', 'subject__name')
    )
    if published_only:
        papers = papers.filter(exam__is_published=True)

    grouped = defaultdict(list)
    order = []
    for paper in papers:
        key = (paper.exam, paper.classroom)
        if key not in grouped:
            order.append(key)
        grouped[key].append(paper)

    cards = []
    bands_by_school = {}
    for exam, classroom in order:
        if exam.school_id not in bands_by_school:
            bands_by_school[exam.school_id] = bands_for_school(exam.school_id)
        results = compute_class_results(exam, classroom, grouped[(exam, classroom)], bands_by_school[exam.school_id])
        row = next((r for r in results['rows'] if r['student'] == student.id), None)
        if row is None:
            continue
        cards.append({
            'exam': exam.id,
            'exam_name': exam.name,
            'academic_year': exam.academic_year,
            'start_date': exam.start_date,
            'end_date': exam.end_date,
            'is_published': exam.is_published,
            'classroom': classroom.id,
            'classroom_name': f'{classroom.name} - {classroom.section}',
            'class_size': results['ranked_count'],
            **{key: row[key] for key in (
                'subjects', 'total', 'max_total', 'percentage', 'grade', 'result', 'rank', 'is_complete',
            )},
        })
    return cards
