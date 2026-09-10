import re
from django.db import models
from django.core.exceptions import ValidationError


def validate_academic_year_format(value):
    """
    Standardizes academic year to YYYY-YYYY format (e.g. 2025-2026).
    """
    if not value:
        return
    norm = normalize_academic_year(value)
    if not re.match(r'^\d{4}-\d{4}$', norm):
        raise ValidationError(
            f"Academic year '{value}' must be in YYYY-YYYY format (e.g. 2025-2026)."
        )
    start_year, end_year = map(int, norm.split('-'))
    if end_year != start_year + 1:
        raise ValidationError(
            f"Academic year '{value}' is invalid. End year must be start year + 1 (e.g. 2025-2026)."
        )


def normalize_academic_year(val):
    """
    Normalizes short forms like '2025-26' to canonical '2025-2026'.
    """
    if not val:
        return val
    val = str(val).strip()
    m = re.match(r'^(\d{4})-(\d{2})$', val)
    if m:
        start_year = m.group(1)
        century = start_year[:2]
        return f"{start_year}-{century}{m.group(2)}"
    return val


class Class(models.Model):
    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='classes',
        help_text="School this class belongs to",
    )
    name = models.CharField(max_length=100, help_text="Class name (e.g. Grade 5)")
    section = models.CharField(max_length=20, help_text="Section name (e.g. A)")
    academic_year = models.CharField(
        max_length=20,
        validators=[validate_academic_year_format],
        help_text="Academic session in YYYY-YYYY format (e.g. 2025-2026)",
    )
    teachers = models.ManyToManyField(
        'accounts.User',
        blank=True,
        related_name='assigned_classes',
        limit_choices_to={'role': 'TEACHER'},
        help_text="Teachers assigned to this class",
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name', 'section']
        verbose_name = 'Class'
        verbose_name_plural = 'Classes'
        unique_together = ('school', 'name', 'section', 'academic_year')
        indexes = [
            models.Index(fields=['school', 'academic_year']),
            models.Index(fields=['school', 'is_active']),
        ]

    def clean(self):
        super().clean()
        if self.academic_year:
            self.academic_year = normalize_academic_year(self.academic_year)
            validate_academic_year_format(self.academic_year)

    def save(self, *args, **kwargs):
        if self.academic_year:
            self.academic_year = normalize_academic_year(self.academic_year)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} - {self.section} ({self.academic_year})"


class Student(models.Model):
    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='students',
        help_text="School this student is enrolled in",
    )
    admission_number = models.CharField(
        max_length=50,
        help_text="Unique admission/roll number within the school",
    )
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100, blank=True)
    date_of_birth = models.DateField(null=True, blank=True)
    class_enrolled = models.ForeignKey(
        Class,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='students',
        help_text="Current active class and section of the student",
    )
    parents = models.ManyToManyField(
        'accounts.User',
        related_name='children',
        blank=True,
        limit_choices_to={'role': 'PARENT'},
        help_text="Parents or guardians linked to this student",
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['admission_number']
        verbose_name = 'Student'
        verbose_name_plural = 'Students'
        unique_together = ('school', 'admission_number')
        indexes = [
            models.Index(fields=['school', 'is_active']),
            models.Index(fields=['school', 'class_enrolled']),
        ]

    def clean(self):
        super().clean()
        if self.class_enrolled and hasattr(self, 'school_id') and self.school_id:
            if self.class_enrolled.school_id != self.school_id:
                raise ValidationError({
                    'class_enrolled': "Cannot assign a student to a class from a different school."
                })

    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}".strip()

    def sync_current_enrollment(self):
        """
        Maintains StudentClassEnrollment historical tracking record
        whenever current class_enrolled is assigned or changed.
        """
        if self.class_enrolled:
            # Mark previous enrollments as non-current if moving to a new class/year
            StudentClassEnrollment.objects.filter(
                student=self,
                is_current=True,
            ).exclude(
                classroom=self.class_enrolled,
                academic_year=self.class_enrolled.academic_year,
            ).update(is_current=False)

            # Get or create current enrollment record
            StudentClassEnrollment.objects.get_or_create(
                school=self.school,
                student=self,
                classroom=self.class_enrolled,
                academic_year=self.class_enrolled.academic_year,
                defaults={'is_current': True},
            )

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        self.sync_current_enrollment()

    def __str__(self):
        return f"{self.full_name} ({self.admission_number})"


class StudentClassEnrollment(models.Model):
    """
    Preserves academic year student class history (e.g. 2024-2025 -> 4-A, 2025-2026 -> 5-A).
    """
    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='enrollments',
        help_text="School this enrollment record belongs to",
    )
    student = models.ForeignKey(
        Student,
        on_delete=models.CASCADE,
        related_name='enrollments',
        help_text="Enrolled student",
    )
    classroom = models.ForeignKey(
        Class,
        on_delete=models.CASCADE,
        related_name='enrollments',
        help_text="Class enrolled in",
    )
    academic_year = models.CharField(
        max_length=20,
        validators=[validate_academic_year_format],
        help_text="Academic session in YYYY-YYYY format (e.g. 2025-2026)",
    )
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    is_current = models.BooleanField(
        default=True,
        help_text="Indicates whether this is the student's active current enrollment",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-academic_year', '-created_at']
        verbose_name = 'Student Class Enrollment'
        verbose_name_plural = 'Student Class Enrollments'
        unique_together = ('student', 'classroom', 'academic_year')
        indexes = [
            models.Index(fields=['school', 'academic_year']),
            models.Index(fields=['student', 'is_current']),
        ]

    def clean(self):
        super().clean()
        if self.academic_year:
            self.academic_year = normalize_academic_year(self.academic_year)
            validate_academic_year_format(self.academic_year)
        if self.student and self.school_id and self.student.school_id != self.school_id:
            raise ValidationError({'student': "Student must belong to the enrollment's school."})
        if self.classroom and self.school_id and self.classroom.school_id != self.school_id:
            raise ValidationError({'classroom': "Classroom must belong to the enrollment's school."})

    def save(self, *args, **kwargs):
        if self.academic_year:
            self.academic_year = normalize_academic_year(self.academic_year)
        if self.classroom and not self.school_id:
            self.school = self.classroom.school
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.student.full_name} -> {self.classroom} [{self.academic_year}]"
