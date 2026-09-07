from django.db import models


class Class(models.Model):
    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='classes',
        help_text="School this class belongs to",
    )
    name = models.CharField(max_length=100, help_text="Class name (e.g. Grade 5)")
    section = models.CharField(max_length=20, help_text="Section name (e.g. A)")
    academic_year = models.CharField(max_length=20, help_text="Academic session (e.g. 2026-2027)")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name', 'section']
        verbose_name = 'Class'
        verbose_name_plural = 'Classes'
        unique_together = ('school', 'name', 'section', 'academic_year')

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
        help_text="Current class and section of the student",
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['admission_number']
        verbose_name = 'Student'
        verbose_name_plural = 'Students'
        unique_together = ('school', 'admission_number')

    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}".strip()

    def __str__(self):
        return f"{self.full_name} ({self.admission_number})"
