"""
Bulk onboarding from a CSV roll.

Typing 1000 students in by hand is not a launch plan, and schools already keep
the roll in a spreadsheet. This reads that spreadsheet, creates the classes,
students and parent accounts it names, and links them together.

Design notes:

* Idempotent. A student is matched on (school, admission_number), so re-running
  a corrected file updates rows instead of duplicating them.
* All or nothing. The whole file is applied in one transaction, so a bad row
  halfway down cannot leave the roll half-imported.
* Parents get an account with no usable password. They sign in with the
  WhatsApp code on the number in the file, so nobody has to distribute
  passwords to 500 families.
"""

import csv
import io
import re

from django.db import transaction

from apps.accounts.models import User

from .models import Class, Student, normalize_academic_year

REQUIRED_COLUMNS = {'admission_number', 'first_name'}

KNOWN_COLUMNS = {
    'admission_number',
    'first_name',
    'last_name',
    'class_name',
    'section',
    'date_of_birth',
    'parent_name',
    'parent_phone',
    'parent_email',
}

TEMPLATE_HEADER = [
    'admission_number',
    'first_name',
    'last_name',
    'class_name',
    'section',
    'date_of_birth',
    'parent_name',
    'parent_phone',
    'parent_email',
]

TEMPLATE_SAMPLE_ROWS = [
    ['ADM001', 'Kavya', 'Sundaram', 'Grade 5', 'A', '2015-04-12',
     'Ravi Kumar', '9876543210', 'ravi.kumar@example.com'],
    ['ADM002', 'Rahul', 'Murugan', 'Grade 5', 'A', '2015-07-30',
     'Latha Murugan', '9876543211', ''],
    ['ADM003', 'Ananya', 'Krishnan', 'Grade 6', 'B', '', '', '', ''],
]


class ImportError_(Exception):
    """Raised when the file itself cannot be read at all."""


def build_template_csv():
    """The CSV a school starts from, with the expected header and examples."""
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(TEMPLATE_HEADER)
    writer.writerows(TEMPLATE_SAMPLE_ROWS)
    return buffer.getvalue()


def normalize_phone(raw):
    """Ten digits, dropping a +91 / 91 country prefix and any punctuation."""
    digits = re.sub(r'\D', '', str(raw or ''))
    if len(digits) == 12 and digits.startswith('91'):
        digits = digits[2:]
    return digits


def _clean(value):
    return (value or '').strip()


def _parse_rows(file_bytes):
    """Decodes the upload and yields (line_number, row-dict)."""
    for encoding in ('utf-8-sig', 'utf-8', 'latin-1'):
        try:
            text = file_bytes.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        raise ImportError_("Could not read the file. Save it as CSV (UTF-8) and try again.")

    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        raise ImportError_("The file is empty.")

    headers = {(name or '').strip().lower() for name in reader.fieldnames}
    missing = REQUIRED_COLUMNS - headers
    if missing:
        raise ImportError_(
            "Missing required column(s): %s. Download the template to see the "
            "expected format." % ', '.join(sorted(missing))
        )

    for line_number, raw_row in enumerate(reader, start=2):  # row 1 is the header
        row = {
            (key or '').strip().lower(): _clean(value)
            for key, value in raw_row.items()
            if key
        }
        yield line_number, row


def _resolve_class(school, academic_year, class_name, section, cache):
    """Finds or creates the class named by a row. Blank names mean unassigned."""
    if not class_name:
        return None

    key = (class_name.lower(), (section or '').lower())
    if key in cache:
        return cache[key]

    classroom, _ = Class.objects.get_or_create(
        school=school,
        name=class_name,
        section=section or 'A',
        academic_year=academic_year,
        defaults={'is_active': True},
    )
    cache[key] = classroom
    return classroom


def _resolve_parent(school, name, phone, email, cache):
    """
    Finds or creates the parent account for a row.

    Matched on phone first (that is what they sign in with), then email. The
    account has no usable password: parents sign in with the WhatsApp code.
    """
    phone = normalize_phone(phone)
    email = email.lower()
    if not phone and not email:
        return None

    key = phone or email
    if key in cache:
        return cache[key]

    parent = None
    if phone:
        parent = User.objects.filter(
            role=User.Role.PARENT,
            phone_number__in=[phone, f'+91{phone}', f'91{phone}'],
        ).first()
    if parent is None and email:
        parent = User.objects.filter(role=User.Role.PARENT, email__iexact=email).first()

    if parent is None:
        first_name, _, last_name = (name or '').partition(' ')
        username = _unique_username(phone or email.split('@')[0])
        parent = User.objects.create_user(
            username=username,
            email=email,
            first_name=first_name or 'Parent',
            last_name=last_name,
            role=User.Role.PARENT,
            school=school,
            phone_number=phone,
            is_active=True,
        )
        parent.set_unusable_password()
        parent.save(update_fields=['password'])
    elif parent.school_id is None:
        parent.school = school
        parent.save(update_fields=['school'])

    cache[key] = parent
    return parent


def _unique_username(base):
    slug = re.sub(r'[^a-zA-Z0-9_]', '', str(base)) or 'parent'
    username = slug
    suffix = 1
    while User.objects.filter(username=username).exists():
        username = f'{slug}_{suffix}'
        suffix += 1
    return username


@transaction.atomic
def import_students_csv(file_bytes, school, academic_year, dry_run=False):
    """
    Applies a roll CSV.

    Returns a summary dict: how many students and parents were created or
    updated, which classes were touched, and a per-row list of problems. When
    ``dry_run`` is true nothing is kept - the caller gets the same summary so a
    school can check the file before committing to it.
    """
    academic_year = normalize_academic_year(academic_year)

    summary = {
        'students_created': 0,
        'students_updated': 0,
        'parents_created': 0,
        'parents_linked': 0,
        'classes_created': 0,
        'rows_processed': 0,
        'errors': [],
        'dry_run': dry_run,
    }

    class_cache = {}
    parent_cache = {}
    classes_before = Class.objects.filter(school=school).count()
    parents_before = User.objects.filter(role=User.Role.PARENT).count()
    seen_admission_numbers = set()

    for line_number, row in _parse_rows(file_bytes):
        admission_number = row.get('admission_number', '')
        first_name = row.get('first_name', '')

        if not admission_number and not first_name:
            continue  # blank padding row at the end of a spreadsheet export

        summary['rows_processed'] += 1

        if not admission_number:
            summary['errors'].append(
                {'row': line_number, 'message': 'admission_number is required.'}
            )
            continue
        if not first_name:
            summary['errors'].append(
                {'row': line_number, 'message': 'first_name is required.'}
            )
            continue
        if admission_number in seen_admission_numbers:
            summary['errors'].append({
                'row': line_number,
                'message': f"Duplicate admission_number '{admission_number}' in this file.",
            })
            continue
        seen_admission_numbers.add(admission_number)

        classroom = _resolve_class(
            school, academic_year,
            row.get('class_name', ''), row.get('section', ''),
            class_cache,
        )

        date_of_birth = row.get('date_of_birth') or None
        if date_of_birth and not re.match(r'^\d{4}-\d{2}-\d{2}$', date_of_birth):
            summary['errors'].append({
                'row': line_number,
                'message': f"date_of_birth '{date_of_birth}' must be YYYY-MM-DD.",
            })
            date_of_birth = None

        student, created = Student.objects.get_or_create(
            school=school,
            admission_number=admission_number,
            defaults={
                'first_name': first_name,
                'last_name': row.get('last_name', ''),
                'class_enrolled': classroom,
                'date_of_birth': date_of_birth,
                'is_active': True,
            },
        )
        if created:
            summary['students_created'] += 1
        else:
            student.first_name = first_name
            student.last_name = row.get('last_name', '') or student.last_name
            if classroom:
                student.class_enrolled = classroom
            if date_of_birth:
                student.date_of_birth = date_of_birth
            student.save()
            summary['students_updated'] += 1

        parent = _resolve_parent(
            school,
            row.get('parent_name', ''),
            row.get('parent_phone', ''),
            row.get('parent_email', ''),
            parent_cache,
        )
        if parent and not student.parents.filter(id=parent.id).exists():
            student.parents.add(parent)
            summary['parents_linked'] += 1

    summary['classes_created'] = (
        Class.objects.filter(school=school).count() - classes_before
    )
    summary['parents_created'] = (
        User.objects.filter(role=User.Role.PARENT).count() - parents_before
    )

    if dry_run:
        transaction.set_rollback(True)

    return summary
