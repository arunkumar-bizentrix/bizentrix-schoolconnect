"""
Printable report card - built from the same data as the report-card API.

Nothing here decides who may see what, or computes a mark: the caller passes
cards produced by `services.report_card`, which already applied publishing
rules, totals, grades and ranks. This module only lays them out on A4.
"""

from io import BytesIO

from django.db.models import Count, Q
from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from apps.attendance.models import Attendance
from apps.students.models import Class

from .grading import bands_for_school

INK = colors.HexColor('#0F172A')
MUTED = colors.HexColor('#475569')
RULE = colors.HexColor('#CBD5E1')
BAND = colors.HexColor('#0F2E6B')
TINT = colors.HexColor('#F1F5F9')
FAIL = colors.HexColor('#B91C1C')

_styles = getSampleStyleSheet()
TITLE = ParagraphStyle('Title', parent=_styles['Title'], fontName='Helvetica-Bold', fontSize=17, leading=21,
                       textColor=INK, spaceAfter=2, alignment=TA_CENTER)
SUB = ParagraphStyle('Sub', parent=_styles['Normal'], fontSize=9, leading=12, textColor=MUTED, alignment=TA_CENTER)
HEADING = ParagraphStyle('Heading', parent=_styles['Normal'], fontName='Helvetica-Bold', fontSize=12, leading=15,
                         textColor=colors.white)
LABEL = ParagraphStyle('Label', parent=_styles['Normal'], fontSize=8, leading=10, textColor=MUTED)
VALUE = ParagraphStyle('Value', parent=_styles['Normal'], fontName='Helvetica-Bold', fontSize=10, leading=13, textColor=INK)
CELL = ParagraphStyle('Cell', parent=_styles['Normal'], fontSize=9.5, leading=12, textColor=INK)
SMALL = ParagraphStyle('Small', parent=_styles['Normal'], fontSize=8, leading=10, textColor=MUTED)


def _fmt(value):
    if value is None:
        return '-'
    value = float(value)
    return str(int(value)) if value == int(value) else f'{value:.1f}'


def _escape(text):
    return (str(text or '')
            .replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))


def _ordinal(rank):
    if rank is None:
        return '-'
    if 11 <= rank % 100 <= 13:
        return f'{rank}th'
    suffix = {1: 'st', 2: 'nd', 3: 'rd'}.get(rank % 10, 'th')
    return f'{rank}{suffix}'


def _attendance_line(student, classroom_id):
    counts = Attendance.objects.filter(student=student, classroom_id=classroom_id).aggregate(
        total=Count('id'),
        attended=Count('id', filter=Q(status__in=[Attendance.Status.PRESENT, Attendance.Status.LATE])),
    )
    total = counts['total'] or 0
    if not total:
        return 'Not recorded'
    days = 'day' if total == 1 else 'days'
    return f"{counts['attended'] * 100 / total:.1f}% ({counts['attended']} of {total} {days})"


def _info_block(school, student, card, classroom):
    teacher = classroom.class_teacher if classroom else None
    teacher_name = (f'{teacher.first_name} {teacher.last_name}'.strip() or teacher.username) if teacher else '-'
    pairs = [
        ('Student', student.full_name), ('Admission number', student.admission_number),
        ('Class', classroom.name if classroom else '-'), ('Section', classroom.section if classroom else '-'),
        ('Academic year', card['academic_year']), ('Class teacher', teacher_name),
        ('Exam', card['exam_name']), ('Attendance this year', _attendance_line(student, card['classroom'])),
    ]
    rows = []
    for index in range(0, len(pairs), 2):
        row = []
        for label, value in pairs[index:index + 2]:
            row.append([Paragraph(label, LABEL), Paragraph(_escape(value), VALUE)])
        rows.append(row)
    table = Table(rows, colWidths=[90 * mm, 90 * mm])
    table.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('LINEBELOW', (0, 0), (-1, -2), 0.25, RULE),
    ]))
    return table


def _marks_table(card):
    header = ['Subject', 'Max', 'Pass', 'Marks', '%', 'Grade', 'Result']
    rows = [header]
    style = [
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9.5),
        ('TEXTCOLOR', (0, 0), (-1, 0), MUTED),
        ('LINEBELOW', (0, 0), (-1, 0), 0.8, INK),
        ('ALIGN', (1, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]
    for index, subject in enumerate(card['subjects'], start=1):
        if not subject['entered']:
            marks, result = 'Not entered', '-'
        elif subject['is_absent']:
            marks, result = 'Absent', 'Fail'
        else:
            marks, result = _fmt(subject['marks_obtained']), ('Pass' if subject['passed'] else 'Fail')
        rows.append([
            Paragraph(_escape(subject['subject']), CELL), subject['max_marks'], subject['pass_marks'],
            marks, _fmt(subject.get('percentage')), subject.get('grade') or '-', result,
        ])
        if result == 'Fail':
            style.append(('TEXTCOLOR', (6, index), (6, index), FAIL))
        if index % 2 == 0:
            style.append(('BACKGROUND', (0, index), (-1, index), TINT))

    total_row = len(rows)
    rows.append(['Total', card['max_total'], '', _fmt(card['total']), _fmt(card['percentage']),
                 card.get('grade') or '-', card['result'].title()])
    style += [
        ('FONTNAME', (0, total_row), (-1, total_row), 'Helvetica-Bold'),
        ('LINEABOVE', (0, total_row), (-1, total_row), 0.8, INK),
    ]
    table = Table(rows, colWidths=[62 * mm, 16 * mm, 16 * mm, 24 * mm, 18 * mm, 18 * mm, 26 * mm], repeatRows=1)
    table.setStyle(TableStyle(style))
    return table


def _summary(card):
    rank = f"{_ordinal(card['rank'])} of {card['class_size']}" if card['rank'] else 'Not ranked'
    result = {'PASS': 'Pass', 'FAIL': 'Fail', 'INCOMPLETE': 'Incomplete - marks pending'}[card['result']]
    cells = [
        ('Total', f"{_fmt(card['total'])} / {card['max_total']}"),
        ('Percentage', f"{_fmt(card['percentage'])}%"),
        ('Grade', card.get('grade') or '-'),
        ('Result', result),
        ('Rank in class', rank),
    ]
    table = Table(
        [[Paragraph(label, LABEL) for label, _ in cells], [Paragraph(_escape(value), VALUE) for _, value in cells]],
        colWidths=[36 * mm] * 5,
    )
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), TINT),
        ('BOX', (0, 0), (-1, -1), 0.5, RULE),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 1), (-1, 1), 7),
    ]))
    return table


def _scale_legend(school_id):
    bands = bands_for_school(school_id)
    cells, previous = [], None
    for label, minimum, _ in bands:
        top = '100' if previous is None else _fmt(float(previous) - (1 if float(previous) == int(previous) else 0.1))
        cells.append(f'{label}: {_fmt(minimum)}-{top}%')
        previous = minimum
    return Paragraph('Grading scale - ' + ' &nbsp;·&nbsp; '.join(cells), SMALL)


def _signatures():
    # Gaps between the columns so each signature gets its own line.
    widths = [52 * mm, 12 * mm, 52 * mm, 12 * mm, 52 * mm]
    table = Table([['', '', '', '', ''], ['Class teacher', '', 'Principal', '', 'Parent / guardian']],
                  colWidths=widths, rowHeights=[16 * mm, None])
    table.setStyle(TableStyle([
        ('LINEABOVE', (0, 1), (0, 1), 0.5, INK),
        ('LINEABOVE', (2, 1), (2, 1), 0.5, INK),
        ('LINEABOVE', (4, 1), (4, 1), 0.5, INK),
        ('FONTSIZE', (0, 1), (-1, 1), 8.5),
        ('TEXTCOLOR', (0, 1), (-1, 1), MUTED),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ]))
    return table


def render_report_card_pdf(*, school, student, cards, compress=True):
    """PDF bytes: one page per exam in `cards`."""
    buffer = BytesIO()
    generated = timezone.localtime().strftime('%d %b %Y, %I:%M %p')

    def decorate(canvas, doc):
        canvas.saveState()
        canvas.setFont('Helvetica', 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(15 * mm, 10 * mm, f'Generated by SchoolConnect on {generated}')
        canvas.drawRightString(195 * mm, 10 * mm, f'{student.admission_number} · page {doc.page}')
        canvas.restoreState()

    doc = SimpleDocTemplate(
        buffer, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm, topMargin=14 * mm, bottomMargin=18 * mm,
        title=f'Report card - {student.full_name}', author=school.name if school else 'SchoolConnect',
        pageCompression=1 if compress else 0,
    )

    classrooms = {c.id: c for c in Class.objects.select_related('class_teacher').filter(id__in={c['classroom'] for c in cards})}
    address = ', '.join(part for part in [(school.address or '').replace('\n', ', ') if school else '',
                                          f'Phone {school.contact_phone}' if school and school.contact_phone else ''] if part)

    story = []
    for index, card in enumerate(cards):
        if index:
            story.append(PageBreak())
        story += [
            Paragraph(_escape(school.name if school else 'School'), TITLE),
            Paragraph(_escape(address) or '&nbsp;', SUB),
            Spacer(1, 6 * mm),
        ]
        banner = Table([[Paragraph('PROGRESS REPORT', HEADING),
                         Paragraph(_escape(card['exam_name']), ParagraphStyle('B', parent=HEADING, alignment=TA_RIGHT))]],
                       colWidths=[90 * mm, 90 * mm])
        banner.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), BAND), ('TOPPADDING', (0, 0), (-1, -1), 7),
                                    ('BOTTOMPADDING', (0, 0), (-1, -1), 7), ('LEFTPADDING', (0, 0), (-1, -1), 9),
                                    ('RIGHTPADDING', (0, 0), (-1, -1), 9)]))
        story += [banner, Spacer(1, 4 * mm), _info_block(school, student, card, classrooms.get(card['classroom'])),
                  Spacer(1, 5 * mm), _marks_table(card), Spacer(1, 5 * mm), _summary(card), Spacer(1, 3 * mm)]

        if not card['is_published']:
            story.append(Paragraph(
                '<font color="#B91C1C"><b>DRAFT</b> - these results are not yet published to parents and may change.</font>',
                CELL))
        story += [Spacer(1, 3 * mm), _scale_legend(school.pk if school else None), Spacer(1, 16 * mm),
                  KeepTogether(_signatures())]

    if not cards:
        story += [Paragraph(_escape(school.name if school else 'School'), TITLE), Spacer(1, 10 * mm),
                  Paragraph(f'No published results for {_escape(student.full_name)} yet.', CELL)]

    doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
    return buffer.getvalue()
