"""
Gives every existing school the approved default grading scale.

Adds rows only; a school that already has bands is left alone. Existing exam
papers keep the pass mark they were created with.
"""

from decimal import Decimal

from django.db import migrations

DEFAULT_GRADE_BANDS = (
    ('A1', Decimal('91'), 'Outstanding'),
    ('A2', Decimal('81'), 'Excellent'),
    ('B1', Decimal('71'), 'Very good'),
    ('B2', Decimal('61'), 'Good'),
    ('C1', Decimal('51'), 'Above average'),
    ('C2', Decimal('41'), 'Average'),
    ('D', Decimal('33'), 'Pass'),
    ('E', Decimal('0'), 'Needs improvement'),
)


def seed(apps, schema_editor):
    School = apps.get_model('schools', 'School')
    GradeBand = apps.get_model('exams', 'GradeBand')
    for school in School.objects.all():
        if GradeBand.objects.filter(school=school).exists():
            continue
        GradeBand.objects.bulk_create([
            GradeBand(school=school, label=label, min_percentage=minimum, description=description)
            for label, minimum, description in DEFAULT_GRADE_BANDS
        ])


def unseed(apps, schema_editor):
    GradeBand = apps.get_model('exams', 'GradeBand')
    labels = [label for label, _, _ in DEFAULT_GRADE_BANDS]
    GradeBand.objects.filter(label__in=labels).delete()


class Migration(migrations.Migration):
    dependencies = [
        ('exams', '0002_grade_bands_and_pass_mark'),
        ('schools', '0001_initial'),
    ]

    operations = [migrations.RunPython(seed, unseed)]
