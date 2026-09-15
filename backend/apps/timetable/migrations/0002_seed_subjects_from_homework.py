"""
Seeds Subject rows from the subject names already typed into homework.

Homework stored its subject as free text, so the school's real subject list
already exists - scattered across those rows. This lifts the distinct names
into Subject so the timetable has something to point at on day one, instead of
asking the admin to retype a list they have effectively already entered.

Names are matched case-insensitively, keeping the most common spelling, so
"maths" and "Maths" become one subject rather than two.
"""

from collections import Counter, defaultdict

from django.db import migrations

# A school with none of its own still gets a sensible starting list.
DEFAULT_SUBJECTS = [
    'English',
    'Mathematics',
    'Science',
    'Social Science',
    'Tamil',
    'Hindi',
    'Computer Science',
    'Physical Education',
]


def seed_subjects(apps, schema_editor):
    Homework = apps.get_model('homework', 'Homework')
    School = apps.get_model('schools', 'School')
    Subject = apps.get_model('timetable', 'Subject')

    used_by_school = defaultdict(Counter)
    for school_id, name in Homework.objects.values_list('school_id', 'subject'):
        cleaned = (name or '').strip()
        if cleaned:
            used_by_school[school_id][cleaned] += 1

    for school in School.objects.all():
        spellings = used_by_school.get(school.id, Counter())

        # Group spellings that differ only by case, keeping the commonest one.
        canonical = {}
        for spelling, count in spellings.most_common():
            key = spelling.lower()
            if key not in canonical:
                canonical[key] = spelling

        names = list(canonical.values()) or DEFAULT_SUBJECTS

        existing = {
            name.lower()
            for name in Subject.objects.filter(school=school).values_list('name', flat=True)
        }
        Subject.objects.bulk_create([
            Subject(school=school, name=name, is_active=True)
            for name in names
            if name.lower() not in existing
        ])


def drop_subjects(apps, schema_editor):
    """Reversing only removes rows this migration could have created."""
    Subject = apps.get_model('timetable', 'Subject')
    Subject.objects.filter(timetable_slots__isnull=True).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('timetable', '0001_initial'),
        ('homework', '0005_homework_due_time'),
        ('schools', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(seed_subjects, drop_subjects),
    ]
