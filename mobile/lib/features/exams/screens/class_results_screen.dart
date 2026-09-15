import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../models/exam_models.dart';
import '../providers/exams_provider.dart';
import 'exams_screen.dart';
import 'report_card_screen.dart';

/// A class's ranked result sheet, for staff.
class ClassResultsScreen extends ConsumerWidget {
  const ClassResultsScreen({super.key, required this.examId, required this.classId});

  final int examId;
  final int classId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (examId: examId, classId: classId);
    final resultsAsync = ref.watch(classResultsProvider(key));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          resultsAsync.value == null
              ? 'Results'
              : '${resultsAsync.value!.classroomName} results',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(classResultsProvider(key)),
        child: resultsAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [ErrorStateView(message: friendlyError(ref, error))]),
          data: (results) => _content(context, results),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ClassResults results) {
    final ranked = results.rows.where((r) => r.rank != null).toList();
    final passed = ranked.where((r) => r.outcome == ExamOutcome.pass).length;
    final average = ranked.isEmpty
        ? null
        : ranked.map((r) => r.percentage).reduce((a, b) => a + b) / ranked.length;
    final incomplete = results.rows.length - ranked.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          '${results.examName} · out of ${results.maxTotal}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(label: 'Class average', value: average == null ? '-' : '${formatMarks(average)}%'),
            const SizedBox(width: 10),
            _Stat(label: 'Passed', value: ranked.isEmpty ? '-' : '$passed / ${ranked.length}'),
            const SizedBox(width: 10),
            _Stat(
              label: 'Incomplete',
              value: '$incomplete',
              warn: incomplete > 0,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (results.rows.isEmpty)
          const EmptyState(icon: Icons.people_outline, title: 'No students in this class'),
        for (final row in results.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ResultTile(
              row: row,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReportCardScreen(studentId: row.studentId)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: warn ? AppColors.statHomeworkBg : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: warn ? AppColors.statHomeworkBg : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: warn ? AppColors.statHomeworkText : AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.row, required this.onTap});

  final ResultRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final podium = row.rank != null && row.rank! <= 3;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: podium ? AppColors.statHomeworkBg : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      row.rank == null ? '-' : '${row.rank}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: podium ? AppColors.statHomeworkText : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.studentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        OutcomeLabel(outcome: row.outcome),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${formatMarks(row.total)}/${row.maxTotal}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        '${formatMarks(row.percentage)}%',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final subject in row.subjects)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: subject.passed == false ? AppColors.statusOverdueBg : AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${subject.subject} ${subject.display}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: subject.passed == false ? AppColors.statusOverdueText : AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pass / Fail / Incomplete in words and colour.
class OutcomeLabel extends StatelessWidget {
  const OutcomeLabel({super.key, required this.outcome});

  final ExamOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final color = switch (outcome) {
      ExamOutcome.pass => AppColors.statusActiveText,
      ExamOutcome.fail => AppColors.statusOverdueText,
      ExamOutcome.incomplete => AppColors.statHomeworkText,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            outcome.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}
