from django.db import migrations


def populate_enrollments(apps, schema_editor):
    Student = apps.get_model('students', 'Student')
    StudentClassEnrollment = apps.get_model('students', 'StudentClassEnrollment')

    for student in Student.objects.filter(class_enrolled__isnull=False):
        classroom = student.class_enrolled
        StudentClassEnrollment.objects.get_or_create(
            school=student.school,
            student=student,
            classroom=classroom,
            academic_year=classroom.academic_year,
            defaults={'is_current': True}
        )


def reverse_populate(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('students', '0003_studentclassenrollment_class_teachers_and_more'),
    ]

    operations = [
        migrations.RunPython(populate_enrollments, reverse_populate),
    ]
