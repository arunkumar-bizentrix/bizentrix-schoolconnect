from django.db.models import Count, Q
from django.http import HttpResponse
from rest_framework import viewsets, permissions, filters, status, parsers
from rest_framework.exceptions import PermissionDenied
from rest_framework.decorators import action
from rest_framework.views import APIView
from rest_framework.response import Response

from apps.accounts.models import User
from apps.accounts.services.accounts import normalize_phone
from apps.schools.services import attach_user_to_school, get_school_for

from .models import Class, Student, StudentClassEnrollment, normalize_academic_year
from .serializers import (
    ClassSerializer,
    StudentSerializer,
    StudentClassEnrollmentSerializer,
)
from .permissions import IsSchoolMember
from .services import ImportError_, build_template_csv, import_students_csv


class ClassViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing academic Classes with tenant isolation & advanced filtering.
    - List classes: GET /api/v1/classes/
    - Filters: ?academic_year=2025-2026&name=Grade 5&section=A&is_active=true&assigned_to_me=true
    """
    serializer_class = ClassSerializer
    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['name', 'section', 'academic_year']
    ordering_fields = ['name', 'section', 'academic_year', 'created_at']

    def filter_queryset(self, queryset):
        queryset = super().filter_queryset(queryset)
        # A client-chosen ?ordering= replaces the default; keep `id` last so
        # paging stays stable whatever the sort.
        ordering = list(queryset.query.order_by)
        if 'id' not in ordering and '-id' not in ordering:
            queryset = queryset.order_by(*ordering, 'id')
        return queryset

    def get_queryset(self):
        user = self.request.user
        school = get_school_for(user)

        queryset = Class.objects.select_related('school', 'class_teacher').prefetch_related('teachers').annotate(
            student_count=Count('students', filter=Q(students__is_active=True), distinct=True),
        )
        if not (user.is_superuser and not user.school):
            queryset = queryset.filter(school=school)

        # Teachers only see classes assigned to them
        if user.role == 'TEACHER':
            queryset = queryset.filter(teachers=user)
        # Parents only see their own children's classes. A subquery rather
        # than a join, so the student_count annotation is not multiplied.
        elif user.role == 'PARENT':
            queryset = queryset.filter(
                id__in=Class.objects.filter(students__parents=user).values('id')
            )

        params = self.request.query_params

        # Filter: academic_year (e.g. 2025-2026 or 2025-26)
        academic_year = params.get('academic_year')
        if academic_year:
            norm_year = normalize_academic_year(academic_year)
            queryset = queryset.filter(academic_year__iexact=norm_year)

        # Filter: name / class_name
        name = params.get('name') or params.get('class_name')
        if name:
            queryset = queryset.filter(name__icontains=name)

        # Filter: section
        section = params.get('section')
        if section:
            queryset = queryset.filter(section__iexact=section)

        # Filter: is_active
        is_active = params.get('is_active')
        if is_active is not None:
            val = is_active.lower() in ['true', '1', 'yes']
            queryset = queryset.filter(is_active=val)

        # Filter: assigned_to_me (for teachers)
        assigned_to_me = params.get('assigned_to_me')
        if assigned_to_me and assigned_to_me.lower() in ['true', '1', 'yes']:
            queryset = queryset.filter(teachers=user)

        # Name and section repeat across academic years, so they alone do not
        # give a total order - and without one, a row can land on two pages
        # or on neither when a client walks every page. `id` breaks the tie.
        return queryset.order_by('name', 'section', 'academic_year', 'id')

    def perform_create(self, serializer):
        user = self.request.user
        if user.role != 'ADMIN' and not user.is_superuser:
            raise PermissionDenied("Only school administrators can create classes.")

        school = attach_user_to_school(user)

        extra = {}
        if 'is_active' not in serializer.validated_data:
            extra['is_active'] = True

        if user.is_superuser and 'school' in serializer.validated_data:
            serializer.save(**extra)
        else:
            serializer.save(school=school, **extra)

    def perform_destroy(self, instance):
        user = self.request.user
        if user.role != 'ADMIN' and not user.is_superuser:
            raise PermissionDenied("Only school administrators can delete classes.")
        instance.delete()


class StudentViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing Students with strict tenant isolation, role scoping, & advanced filtering.
    - List students: GET /api/v1/students/
    - Filters: ?academic_year=2025-2026&class_id=1&section=A&admission_number=ADM001&name=Arun
    """
    serializer_class = StudentSerializer
    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['admission_number', 'first_name', 'last_name']
    ordering_fields = ['admission_number', 'first_name', 'last_name', 'created_at']

    def get_queryset(self):
        user = self.request.user
        school = get_school_for(user)

        if user.is_superuser and not user.school:
            queryset = Student.objects.select_related(
                'school', 'class_enrolled'
            ).prefetch_related('parents', 'enrollments').all()
        else:
            queryset = Student.objects.select_related(
                'school', 'class_enrolled'
            ).prefetch_related('parents', 'enrollments').filter(school=school)

        # Role-based restriction: Parents only see their own children; Teachers see assigned class students
        if user.role == 'PARENT':
            queryset = queryset.filter(parents=user)
        elif user.role == 'TEACHER':
            queryset = queryset.filter(class_enrolled__teachers=user)

        params = self.request.query_params

        # Filter: class_id
        class_id = params.get('class_id')
        if class_id:
            # Check if class belongs to user's school (unless superuser)
            if not user.is_superuser:
                class_exists = Class.objects.filter(id=class_id, school=school).exists()
                if not class_exists:
                    return queryset.none()
            queryset = queryset.filter(class_enrolled_id=class_id)

        # Filter: academic_year (matches active enrollment or historical enrollment)
        academic_year = params.get('academic_year')
        if academic_year:
            norm_year = normalize_academic_year(academic_year)
            queryset = queryset.filter(
                Q(class_enrolled__academic_year__iexact=norm_year) |
                Q(enrollments__academic_year__iexact=norm_year)
            ).distinct()

        # Filter: section
        section = params.get('section')
        if section:
            queryset = queryset.filter(class_enrolled__section__iexact=section)

        # Filter: admission_number
        adm = params.get('admission_number')
        if adm:
            queryset = queryset.filter(admission_number__icontains=adm)

        # Filter: name search (first_name, last_name, or full name)
        name = params.get('name')
        if name:
            # Match a full-name query such as "Pandi Kumar" across separate
            # first/last-name columns. Every word must match one searchable
            # field, while a single admission number still works normally.
            for term in name.split():
                queryset = queryset.filter(
                    Q(first_name__icontains=term) |
                    Q(last_name__icontains=term) |
                    Q(admission_number__icontains=term)
                )

        first_name = params.get('first_name')
        if first_name:
            queryset = queryset.filter(first_name__icontains=first_name)

        last_name = params.get('last_name')
        if last_name:
            queryset = queryset.filter(last_name__icontains=last_name)

        # Filter: is_active
        is_active = params.get('is_active')
        if is_active is not None:
            val = is_active.lower() in ['true', '1', 'yes']
            queryset = queryset.filter(is_active=val)

        return queryset

    def perform_create(self, serializer):
        user = self.request.user
        if user.role != 'ADMIN' and not user.is_superuser:
            raise PermissionDenied("Only school administrators can add students.")

        school = attach_user_to_school(user)

        extra = {}
        if 'is_active' not in serializer.validated_data:
            extra['is_active'] = True

        if user.is_superuser and 'school' in serializer.validated_data:
            serializer.save(**extra)
        else:
            serializer.save(school=school, **extra)

    def perform_destroy(self, instance):
        user = self.request.user
        if user.role != 'ADMIN' and not user.is_superuser:
            raise PermissionDenied("Only school administrators can remove students.")
        instance.delete()

    @action(detail=True, methods=['get', 'post'], url_path='enrollments')
    def enrollments(self, request, pk=None):
        """
        GET /api/v1/students/<id>/enrollments/ -> Lists student's academic year enrollment history
        POST /api/v1/students/<id>/enrollments/ -> Enrolls/promotes student into class for academic year
        """
        student = self.get_object()

        if request.method == 'GET':
            enrollments = student.enrollments.select_related('classroom').all()
            serializer = StudentClassEnrollmentSerializer(enrollments, many=True)
            return Response(serializer.data, status=status.HTTP_200_OK)

        elif request.method == 'POST':
            if request.user.role != 'ADMIN' and not request.user.is_superuser:
                return Response(
                    {"detail": "Only school administrators can manage class enrollments."},
                    status=status.HTTP_403_FORBIDDEN
                )

            serializer = StudentClassEnrollmentSerializer(
                data=request.data,
                context={'request': request, 'student': student}
            )
            serializer.is_valid(raise_exception=True)

            classroom = serializer.validated_data['classroom']
            academic_year = serializer.validated_data['academic_year']

            # Update current active class on student
            student.class_enrolled = classroom
            student.save()

            # Ensure enrollment instance
            enrollment, _ = StudentClassEnrollment.objects.update_or_create(
                student=student,
                classroom=classroom,
                academic_year=academic_year,
                defaults={
                    'school': student.school,
                    'is_current': True,
                    'start_date': serializer.validated_data.get('start_date'),
                    'end_date': serializer.validated_data.get('end_date'),
                }
            )

            out_serializer = StudentClassEnrollmentSerializer(enrollment)
            return Response(out_serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], url_path='link-parent')
    def link_parent(self, request, pk=None):
        """
        POST /api/v1/students/<id>/link-parent/
        Admin-controlled parent-student linking.
        Payload: {"parent_id": 1} or {"email": "..."} or {"phone_number": "..."}
        """
        if request.user.role != 'ADMIN' and not request.user.is_superuser:
            return Response(
                {"detail": "Only school administrators can link parents to students."},
                status=status.HTTP_403_FORBIDDEN
            )

        student = self.get_object()

        parent_id = request.data.get('parent_id')
        email = request.data.get('email')
        phone = request.data.get('phone_number') or request.data.get('phone')

        # Only this school's parents, and only an exact match: "98111" used to
        # link whichever parent's number happened to contain it.
        parents = User.objects.filter(role=User.Role.PARENT, school_id=student.school_id)
        parent = None
        if parent_id:
            parent = parents.filter(id=parent_id).first()
        elif email:
            parent = parents.filter(email__iexact=str(email).strip()).first()
        elif phone:
            digits = normalize_phone(phone)
            if len(digits) == 10:
                matches = list(parents.filter(phone_number=digits)[:2])
                if len(matches) > 1:
                    return Response(
                        {"detail": "More than one parent uses that number. Link by choosing the parent instead."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                parent = matches[0] if matches else None

        if not parent:
            return Response(
                {"detail": "Parent user account not found. Please verify the parent user ID, email, or phone."},
                status=status.HTTP_404_NOT_FOUND
            )

        student.parents.add(parent)
        return Response({
            "success": True,
            "message": f"Parent '{parent.first_name or parent.username}' successfully linked to student '{student.full_name}'.",
            "student_id": student.id,
            "parent_id": parent.id,
            "parents": list(student.parents.values_list('id', flat=True)),
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], url_path='unlink-parent')
    def unlink_parent(self, request, pk=None):
        """
        POST /api/v1/students/<id>/unlink-parent/
        Admin-controlled parent-student unlinking.
        """
        if request.user.role != 'ADMIN' and not request.user.is_superuser:
            return Response(
                {"detail": "Only school administrators can unlink parents from students."},
                status=status.HTTP_403_FORBIDDEN
            )

        student = self.get_object()
        parent_id = request.data.get('parent_id')
        if not parent_id:
            return Response({"detail": "parent_id is required."}, status=status.HTTP_400_BAD_REQUEST)

        student.parents.remove(parent_id)
        return Response({
            "success": True,
            "message": f"Parent unlinked from student '{student.full_name}'.",
            "student_id": student.id,
            "parents": list(student.parents.values_list('id', flat=True)),
        }, status=status.HTTP_200_OK)


class ParentChildrenView(APIView):
    """
    GET /api/v1/parent/children/
    Returns strictly the authenticated parent's linked children.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role != 'PARENT':
            return Response([], status=status.HTTP_200_OK)

        children = user.children.filter(is_active=True).select_related('class_enrolled', 'school')
        data = [
            {
                'id': child.id,
                'first_name': child.first_name,
                'last_name': child.last_name,
                'full_name': child.full_name,
                'admission_number': child.admission_number,
                'class_id': child.class_enrolled_id,
                'class_name': str(child.class_enrolled) if child.class_enrolled else 'Unassigned',
                'academic_year': child.class_enrolled.academic_year if child.class_enrolled else None,
                'date_of_birth': child.date_of_birth,
                'is_active': child.is_active,
            }
            for child in children
        ]
        return Response(data, status=status.HTTP_200_OK)



class StudentImportView(APIView):
    """
    POST /api/v1/students/import/    multipart: file=<roll.csv>[&dry_run=true]
    GET  /api/v1/students/import/    downloads the CSV template

    Bulk-onboards a school roll: creates the classes and students named in the
    file, creates a parent account per phone number, and links them. Admin
    only - this writes across the whole roll.

    Pass dry_run=true to validate a file and see the summary without keeping
    any of it.
    """
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [parsers.MultiPartParser, parsers.FormParser]

    MAX_UPLOAD_BYTES = 5 * 1024 * 1024

    def _reject_non_admin(self, request):
        if request.user.role != User.Role.ADMIN and not request.user.is_superuser:
            return Response(
                {"detail": "Only school administrators can import the student roll."},
                status=status.HTTP_403_FORBIDDEN,
            )
        return None

    def get(self, request):
        denied = self._reject_non_admin(request)
        if denied:
            return denied

        response = HttpResponse(build_template_csv(), content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="student_roll_template.csv"'
        return response

    def post(self, request):
        denied = self._reject_non_admin(request)
        if denied:
            return denied

        upload = request.FILES.get('file')
        if upload is None:
            return Response(
                {"detail": "Attach the roll as a CSV file in the 'file' field."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if upload.size > self.MAX_UPLOAD_BYTES:
            return Response(
                {"detail": "That file is larger than 5 MB. Split it into smaller files."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        raw = str(request.data.get('dry_run', '')).lower()
        dry_run = raw in ('1', 'true', 'yes')

        academic_year = (
            request.data.get('academic_year')
            or normalize_academic_year(request.query_params.get('academic_year', ''))
            or None
        )
        if not academic_year:
            from django.utils import timezone
            today = timezone.localdate()
            start = today.year if today.month >= 6 else today.year - 1
            academic_year = f'{start}-{start + 1}'

        school = attach_user_to_school(request.user)
        if school is None:
            return Response(
                {"detail": "No school is set up yet."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            summary = import_students_csv(
                upload.read(), school, academic_year, dry_run=dry_run
            )
        except ImportError_ as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        summary['academic_year'] = academic_year
        return Response(summary, status=status.HTTP_200_OK)
