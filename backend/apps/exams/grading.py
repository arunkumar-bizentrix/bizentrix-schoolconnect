"""
Academic grades from percentages.

The school's scale lives in GradeBand rows so it can change without a code
release. A school without rows yet uses DEFAULT_GRADE_BANDS, the scale the
school approved on 15 Sep 2026:

    A1 91-100   A2 81-90   B1 71-80   B2 61-70
    C1 51-60    C2 41-50   D  33-40   E  0-32

D is a pass: the default pass mark for a paper is 33%.

A band is defined only by its lowest percentage; a score gets the band with
the highest minimum it reaches. Grades are taken from the percentage as it is
displayed (one decimal), so the grade can never disagree with the number the
parent sees - 90.95% shows as "91%" and is graded A1, not A2.
"""

from decimal import ROUND_HALF_UP, Decimal

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

DEFAULT_PASS_PERCENTAGE = 33


def bands_for_school(school):
    """The school's bands, highest first, as (label, min_percentage, description)."""
    from .models import GradeBand

    school_id = getattr(school, 'pk', school)
    rows = list(
        GradeBand.objects.filter(school_id=school_id)
        .order_by('-min_percentage')
        .values_list('label', 'min_percentage', 'description')
    )
    return rows or list(DEFAULT_GRADE_BANDS)


def displayed_percentage(value):
    return Decimal(str(value)).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP)


def grade_for(percentage, bands):
    """The label for a percentage, or None when there is nothing to grade."""
    if percentage is None:
        return None
    shown = displayed_percentage(percentage)
    for label, minimum, _description in bands:
        if shown >= Decimal(str(minimum)):
            return label
    return None


def validate_bands(bands):
    """
    Checks a proposed scale. `bands` is a list of dicts with label and
    min_percentage. Returns a list of problems in words; empty means valid.
    """
    problems = []
    if not bands:
        return ['Add at least one grade.']
    if len(bands) > 15:
        problems.append('A grading scale can have at most 15 grades.')

    labels, minimums = set(), set()
    for band in bands:
        label = str(band.get('label', '')).strip()
        if not label:
            problems.append('Every grade needs a label.')
            continue
        if len(label) > 8:
            problems.append(f'"{label}" is too long - use up to 8 characters.')
        if label.upper() in labels:
            problems.append(f'The grade "{label}" appears twice.')
        labels.add(label.upper())

        try:
            minimum = Decimal(str(band.get('min_percentage')))
        except Exception:
            problems.append(f'"{label}" needs a lowest percentage.')
            continue
        if minimum < 0 or minimum > 100:
            problems.append(f'"{label}" must start between 0 and 100%.')
        if minimum in minimums:
            problems.append(f'Two grades start at {minimum:g}%.')
        minimums.add(minimum)

    if minimums and Decimal('0') not in minimums:
        problems.append('One grade must start at 0% so every score gets a grade.')
    return problems
