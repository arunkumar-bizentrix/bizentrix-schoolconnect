from django.db import transaction
from django.http import HttpResponse
from django.utils.text import slugify
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.schools.services import attach_user_to_school, get_school_for
from apps.students.access import student_for_report
from apps.students.models import Class, Student
from apps.timetable.models import Subject

from .grading import DEFAULT_GRADE_BANDS, bands_for_school, validate_bands
from .models import Exam, ExamPaper, GradeBand, Mark
from .pdf import render_report_card_pdf
from .serializers import (
    ExamPaperSerializer,
    GradeBandSerializer,
    ExamSerializer,
    MarkSheetSubmitSerializer,
)
from .services import (
    ExamError,
    can_enter_marks,
    compute_class_results,
    missing_marks,
    publish_exam,
    report_card,
    unpublish_exam,
)


def _is_admin(user):
    return user.is_superuser or user.role == 'ADMIN'


class IsSchoolMember(permissions.BasePermission):
    """Signed in, at an active school. Finer rules live in each view."""

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if user.is_superuser:
            return True
        school = get_school_for(user)
        return bool(school and school.is_active)


def _paper_queryset_for(user):
    """Papers a user may see: admin all, teacher their classes, parent their children's published ones."""
    school = get_school_for(user)
    queryset = ExamPaper.objects.select_related('exam', 'classroom', 'subject')
    if not (user.is_superuser and not user.school):
        queryset = queryset.filter(exam__school=school)

    if _is_admin(user):
        return queryset
    if user.role == 'TEACHER':
        return queryset.filter(classroom__teachers=user).distinct()
    if user.role == 'PARENT':
        children = Student.objects.filter(parents=user, is_active=True)
        return queryset.filter(exam__is_published=True).filter(
            Q(classroom__students__in=children) | Q(marks__student__in=children)
        ).distinct()
    return queryset.none()


class ExamViewSet(viewsets.ModelViewSet):
    """
    GET    /api/v1/exams/                     exams visible to the user
    POST   /api/v1/exams/                     admin: create with its papers
    PATCH  /api/v1/exams/{id}/                admin: rename, change dates
    DELETE /api/v1/exams/{id}/                admin: only before any mark exists
    GET    /api/v1/exams/{id}/papers/?class_id=
    POST   /api/v1/exams/{id}/add-papers/     admin: more classes or subjects
    GET    /api/v1/exams/{id}/results/?class_id=   staff: ranked results
    GET    /api/v1/exams/{id}/progress/       admin: marks still missing
    POST   /api/v1/exams/{id}/publish/        admin
    POST   /api/v1/exams/{id}/unpublish/      admin
    """

    serializer_class = ExamSerializer
    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]

    def get_queryset(self):
        user = self.request.user
        queryset = Exam.objects.select_related('created_by').prefetch_related(
            'papers__classroom', 'papers__subject'
        )
        if not (user.is_superuser and not user.school):
            queryset = queryset.filter(school=get_school_for(user))

        if user.role == 'TEACHER':
            queryset = queryset.filter(papers__classroom__teachers=user).distinct()
        elif user.role == 'PARENT':
            exam_ids = _paper_queryset_for(user).values_list('exam_id', flat=True)
            queryset = queryset.filter(id__in=exam_ids)
        elif not _is_admin(user):
            queryset = queryset.none()

        params = self.request.query_params
        if params.get('academic_year'):
            queryset = queryset.filter(academic_year=params['academic_year'])
        if params.get('class_id'):
            queryset = queryset.filter(papers__classroom_id=params['class_id']).distinct()
        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if self.request.user.is_authenticated:
            context['school'] = get_school_for(self.request.user)
        return context

    def _require_admin(self):
        if not _is_admin(self.request.user):
            raise PermissionDenied('Only school administrators can manage exams.')

    def perform_create(self, serializer):
        self._require_admin()
        user = self.request.user
        serializer.save(school=attach_user_to_school(user), created_by=user)

    def perform_update(self, serializer):
        self._require_admin()
        serializer.save()

    def perform_destroy(self, instance):
        self._require_admin()
        if Mark.objects.filter(paper__exam=instance).exists():
            raise ValidationError(
                'Marks have already been entered for this exam, so it cannot be deleted.'
            )
        instance.delete()

    # --- papers -------------------------------------------------------------

    @action(detail=True, methods=['get'])
    def papers(self, request, pk=None):
        exam = self.get_object()
        user = request.user
        papers = _paper_queryset_for(user).filter(exam=exam).annotate(
            entered_count=Count('marks', distinct=True)
        )
        class_id = request.query_params.get('class_id')
        if class_id:
            papers = papers.filter(classroom_id=class_id)

        serializer = ExamPaperSerializer(
            papers.order_by('classroom__name', 'classroom__section', 'subject__name'),
            many=True,
            context={'can_enter_marks': lambda paper: can_enter_marks(user, paper)},
        )
        return Response(serializer.data)

    @action(detail=True, methods=['post'], url_path='add-papers')
    def add_papers(self, request, pk=None):
        self._require_admin()
        exam = self.get_object()
        school = get_school_for(request.user)

        classroom_ids = request.data.get('classroom_ids') or []
        subject_ids = request.data.get('subject_ids') or []
        try:
            max_marks = int(request.data.get('max_marks', 100))
            pass_marks = int(request.data.get('pass_marks', 33))
        except (TypeError, ValueError):
            raise ValidationError('Maximum and pass marks must be whole numbers.')
        if max_marks <= 0 or pass_marks > max_marks or pass_marks < 0:
            raise ValidationError('Pass marks must be between 0 and the maximum marks.')

        classrooms = Class.objects.filter(id__in=classroom_ids, school=school)
        subjects = Subject.objects.filter(id__in=subject_ids, school=school)
        existing = set(exam.papers.values_list('classroom_id', 'subject_id'))
        new_papers = [
            ExamPaper(exam=exam, classroom=c, subject=s, max_marks=max_marks, pass_marks=pass_marks)
            for c in classrooms
            for s in subjects
            if (c.id, s.id) not in existing
        ]
        ExamPaper.objects.bulk_create(new_papers)
        return Response({'added': len(new_papers)}, status=status.HTTP_201_CREATED)

    # --- results ------------------------------------------------------------

    @action(detail=True, methods=['get'])
    def results(self, request, pk=None):
        """The class's ranked result sheet. Staff only - parents get the report card."""
        exam = self.get_object()
        user = request.user
        if user.role == 'PARENT':
            raise PermissionDenied("Parents see results on their child's report card.")

        class_id = request.query_params.get('class_id')
        if not class_id:
            raise ValidationError({'class_id': 'Choose a class.'})
        classroom = Class.objects.filter(id=class_id, school=exam.school).first()
        if classroom is None:
            raise ValidationError({'class_id': 'Class not found.'})
        if user.role == 'TEACHER' and not classroom.teachers.filter(id=user.id).exists():
            raise PermissionDenied('You can only see results for classes you teach.')

        results = compute_class_results(exam, classroom)
        return Response({
            'exam': exam.id,
            'exam_name': exam.name,
            'is_published': exam.is_published,
            'classroom': classroom.id,
            'classroom_name': f'{classroom.name} - {classroom.section}',
            'max_total': results['max_total'],
            'ranked_count': results['ranked_count'],
            'papers': [
                {
                    'id': paper.id,
                    'subject': paper.subject.name,
                    'max_marks': paper.max_marks,
                    'pass_marks': paper.pass_marks,
                }
                for paper in results['papers']
            ],
            'rows': results['rows'],
        })

    @action(detail=True, methods=['get'])
    def progress(self, request, pk=None):
        self._require_admin()
        exam = self.get_object()
        missing = missing_marks(exam)
        return Response({
            'missing_total': sum(missing.values()),
            'missing_by_class': missing,
        })

    @action(detail=True, methods=['post'])
    def publish(self, request, pk=None):
        self._require_admin()
        exam = self.get_object()
        allow_incomplete = str(request.data.get('allow_incomplete', '')).lower() in ('1', 'true')
        try:
            notified = publish_exam(exam, allow_incomplete=allow_incomplete)
        except ExamError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'published': True, 'parents_notified': notified})

    @action(detail=True, methods=['post'])
    def unpublish(self, request, pk=None):
        self._require_admin()
        exam = self.get_object()
        unpublish_exam(exam)
        return Response({'published': False})


class ExamPaperViewSet(viewsets.GenericViewSet):
    """
    PATCH  /api/v1/exam-papers/{id}/          admin: max/pass marks, date
    DELETE /api/v1/exam-papers/{id}/          admin: only before marks exist
    GET    /api/v1/exam-papers/{id}/marks/    the mark-entry sheet
    POST   /api/v1/exam-papers/{id}/marks/    save marks for many students at once
    """

    serializer_class = ExamPaperSerializer
    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]

    def get_queryset(self):
        return _paper_queryset_for(self.request.user)

    def partial_update(self, request, pk=None):
        if not _is_admin(request.user):
            raise PermissionDenied('Only school administrators can change a paper.')
        paper = self.get_object()
        serializer = ExamPaperSerializer(paper, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def destroy(self, request, pk=None):
        if not _is_admin(request.user):
            raise PermissionDenied('Only school administrators can remove a paper.')
        paper = self.get_object()
        if paper.marks.exists():
            raise ValidationError('Marks have been entered for this paper, so it cannot be removed.')
        paper.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['get', 'post'])
    def marks(self, request, pk=None):
        paper = self.get_object()
        user = request.user
        if user.role == 'PARENT':
            raise PermissionDenied("Parents see marks on their child's report card.")

        if request.method == 'GET':
            return Response(self._sheet(paper, user))

        if not can_enter_marks(user, paper):
            raise PermissionDenied(
                f'Marks for {paper.subject.name} are entered by the teacher who teaches it.'
            )
        if paper.exam.is_published:
            raise ValidationError(
                'These results are published. Ask the admin to unpublish them before correcting marks.'
            )

        submitted = MarkSheetSubmitSerializer(data=request.data)
        submitted.is_valid(raise_exception=True)
        entries = submitted.validated_data['entries']

        allowed_students = set(
            Student.objects.filter(
                Q(class_enrolled=paper.classroom, is_active=True) | Q(marks__paper=paper)
            ).values_list('id', flat=True)
        )
        errors = {}
        for entry in entries:
            student_id = entry['student']
            if student_id not in allowed_students:
                errors[str(student_id)] = 'This student is not in the class.'
                continue
            marks = entry.get('marks_obtained')
            if not entry.get('is_absent') and marks is not None and marks > paper.max_marks:
                errors[str(student_id)] = f'Marks cannot be more than {paper.max_marks}.'
        if errors:
            raise ValidationError({'entries': errors})

        saved = cleared = 0
        with transaction.atomic():
            now = timezone.now()
            existing = {m.student_id: m for m in Mark.objects.select_for_update().filter(paper=paper)}
            to_create, to_update = [], []
            for entry in entries:
                student_id = entry['student']
                is_absent = entry.get('is_absent', False)
                marks = None if is_absent else entry.get('marks_obtained')
                current = existing.get(student_id)

                if not is_absent and marks is None:
                    # An emptied box removes the mark rather than storing a zero.
                    if current is not None:
                        current.delete()
                        cleared += 1
                    continue

                if current is None:
                    to_create.append(Mark(
                        paper=paper, student_id=student_id, marks_obtained=marks,
                        is_absent=is_absent, remarks=entry.get('remarks', ''), entered_by=user,
                    ))
                else:
                    current.marks_obtained = marks
                    current.is_absent = is_absent
                    current.remarks = entry.get('remarks', '')
                    current.entered_by = user
                    current.updated_at = now  # bulk_update skips auto_now
                    to_update.append(current)

            Mark.objects.bulk_create(to_create)
            Mark.objects.bulk_update(
                to_update, ['marks_obtained', 'is_absent', 'remarks', 'entered_by', 'updated_at']
            )
            saved = len(to_create) + len(to_update)

        return Response({'saved': saved, 'cleared': cleared, **self._sheet(paper, user)})

    def _sheet(self, paper, user):
        marks = {m.student_id: m for m in paper.marks.all()}
        students = Student.objects.filter(
            Q(class_enrolled=paper.classroom, is_active=True) | Q(id__in=list(marks))
        ).distinct().order_by('first_name', 'last_name')
        return {
            'paper': ExamPaperSerializer(
                paper, context={'can_enter_marks': lambda p: can_enter_marks(user, p)}
            ).data,
            'exam_name': paper.exam.name,
            'is_published': paper.exam.is_published,
            'students': [
                {
                    'student': student.id,
                    'student_name': student.full_name,
                    'admission_number': student.admission_number,
                    'marks_obtained': (
                        float(marks[student.id].marks_obtained)
                        if student.id in marks and marks[student.id].marks_obtained is not None
                        else None
                    ),
                    'is_absent': marks[student.id].is_absent if student.id in marks else False,
                    'remarks': marks[student.id].remarks if student.id in marks else '',
                }
                for student in students
            ],
        }


class ReportCardView(APIView):
    """
    GET /api/v1/report-card/?student_id=
    A student's marksheet for every exam: subject marks and grades, total,
    percentage, result and rank. Parents see only published exams, only for
    their own children; teachers see students of the classes they teach.
    """

    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]

    def get(self, request):
        student = student_for_report(request, request.query_params.get('student_id'))
        return Response({
            'student': student.id,
            'student_name': student.full_name,
            'admission_number': student.admission_number,
            'classroom_name': (
                f'{student.class_enrolled.name} - {student.class_enrolled.section}'
                if student.class_enrolled else None
            ),
            'exams': report_card(student, published_only=request.user.role == 'PARENT'),
        })


class ReportCardPdfView(APIView):
    """
    GET /api/v1/report-card/pdf/?student_id=&exam_id=
    The printable report card. With exam_id, that exam only; without, every
    exam the caller may see (one page each). Same access rules as the JSON
    report card - a parent gets published results for their own child only.
    """

    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]

    def get(self, request):
        student = student_for_report(request, request.query_params.get('student_id'))
        cards = report_card(student, published_only=request.user.role == 'PARENT')

        exam_id = request.query_params.get('exam_id')
        if exam_id:
            cards = [card for card in cards if str(card['exam']) == str(exam_id)]
            if not cards:
                # Unpublished for a parent, or not this student's exam: the
                # same answer either way, so nothing leaks about which.
                raise NotFound('No results for that exam.')

        pdf = render_report_card_pdf(school=student.school, student=student, cards=cards)
        name_part = cards[0]['exam_name'] if len(cards) == 1 else 'all-exams'
        filename = slugify(f'report-card-{student.admission_number}-{name_part}') + '.pdf'

        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'inline; filename="{filename}"'
        response['Cache-Control'] = 'private, no-store'
        response['X-Content-Type-Options'] = 'nosniff'
        return response


class GradeScaleView(APIView):
    """
    GET /api/v1/grade-scale/   the school's grading scale (any signed-in member)
    PUT /api/v1/grade-scale/   admin: replace the whole scale at once

    The scale is replaced as a unit rather than edited row by row, so it is
    never half-changed: every save is checked for duplicates and for a band
    starting at 0% before anything is written.
    """

    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]

    def _payload(self, school):
        is_default = not GradeBand.objects.filter(school=school).exists()
        return {
            'is_default': is_default,
            'bands': [
                {'label': label, 'min_percentage': float(minimum), 'description': description}
                for label, minimum, description in bands_for_school(school)
            ],
        }

    def get(self, request):
        return Response(self._payload(get_school_for(request.user)))

    def put(self, request):
        if not _is_admin(request.user):
            raise PermissionDenied('Only school administrators can change the grading scale.')

        serializer = GradeBandSerializer(data=request.data.get('bands', []), many=True)
        serializer.is_valid(raise_exception=True)
        bands = serializer.validated_data
        problems = validate_bands(bands)
        if problems:
            return Response({'detail': ' '.join(problems), 'problems': problems}, status=status.HTTP_400_BAD_REQUEST)

        school = attach_user_to_school(request.user)
        with transaction.atomic():
            GradeBand.objects.filter(school=school).delete()
            GradeBand.objects.bulk_create([
                GradeBand(
                    school=school,
                    label=band['label'].strip(),
                    min_percentage=band['min_percentage'],
                    description=band.get('description', '').strip(),
                )
                for band in bands
            ])
        return Response(self._payload(school))
