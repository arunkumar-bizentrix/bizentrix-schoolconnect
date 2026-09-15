import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../models/exam_models.dart';
import '../providers/exams_provider.dart';
import 'exams_screen.dart';

/// A student's marksheet across exams, newest first.
///
/// Parents see published exams only; staff also see drafts, marked as such.
class ReportCardScreen extends ConsumerWidget {
  const ReportCardScreen({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(reportCardProvider(studentId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('Report card', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportCardProvider(studentId)),
        child: cardAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [ErrorStateView(message: friendlyError(ref, error))]),
          data: (card) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                card.studentName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (card.classroomName != null) card.classroomName!,
                  if (card.admissionNumber.isNotEmpty) 'Adm. no. ${card.admissionNumber}',
                ].join(' · '),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              if (card.exams.isEmpty)
                const EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No results yet',
                  message: 'Exam results appear here once the school publishes them.',
                ),
              for (final exam in card.exams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ReportCardExamCard(exam: exam),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportCardExamCard extends StatelessWidget {
  const ReportCardExamCard({super.key, required this.exam});

  final ReportCardExam exam;

  @override
  Widget build(BuildContext context) {
    final strong = exam.outcome == ExamOutcome.pass;
    final band = strong ? AppColors.primaryDark : (exam.outcome == ExamOutcome.fail ? AppColors.statusOverdueText : AppColors.statHomeworkText);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: band,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exam.examName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    if (!exam.isPublished) const PublishStateChip(isPublished: false),
                  ],
                ),
                Text(
                  '${exam.classroomName} · ${exam.academicYear}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${formatMarks(exam.percentage)}%',
                            style: const TextStyle(
                              fontSize: 34,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatMarks(exam.total)} of ${exam.maxTotal} marks · ${exam.outcome.label}',
                            style: const TextStyle(fontSize: 12.5, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    if (exam.rank != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            ordinal(exam.rank!),
                            style: const TextStyle(fontSize: 26, height: 1, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'rank of ${exam.classSize}',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                for (final subject in exam.subjects) _SubjectLine(subject: subject),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectLine extends StatelessWidget {
  const _SubjectLine({required this.subject});

  final SubjectMark subject;

  @override
  Widget build(BuildContext context) {
    final fraction = subject.entered && !subject.isAbsent && subject.maxMarks > 0
        ? ((subject.marks ?? 0) / subject.maxMarks).clamp(0.0, 1.0)
        : 0.0;
    final failed = subject.passed == false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subject.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              Text(
                subject.isAbsent ? 'Absent' : '${subject.display} / ${subject.maxMarks}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: failed ? AppColors.statusOverdueText : AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: AppColors.surfaceElevated,
              color: failed ? AppColors.statusOverdueText : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
