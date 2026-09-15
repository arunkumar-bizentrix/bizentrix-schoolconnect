import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/role_access.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/exam_models.dart';
import '../providers/exams_provider.dart';
import 'class_results_screen.dart';
import 'exams_screen.dart';
import 'mark_entry_screen.dart';

/// One exam, class by class: which papers exist, how far marks entry has got,
/// the ranked results, and - for the admin - publishing.
class ExamDetailScreen extends ConsumerStatefulWidget {
  const ExamDetailScreen({super.key, required this.examId, required this.title});

  final int examId;
  final String title;

  @override
  ConsumerState<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends ConsumerState<ExamDetailScreen> {
  int? _classId;
  bool _busy = false;

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.statusOverdueText : AppColors.statusActiveText,
      ),
    );
  }

  Future<void> _publish(ExamModel exam) async {
    final actions = ref.read(examActionsProvider);
    setState(() => _busy = true);
    final missing = await actions.missingMarks(exam.id);
    if (!mounted) return;
    setState(() => _busy = false);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          missing > 0 ? '$missing marks not entered' : 'Publish results?',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          missing > 0
              ? 'Some students have no mark for a subject yet, so their totals and ranks will be incomplete. '
                  'Publish anyway, or go back and finish marks entry?'
              : 'Parents will see marks, totals and ranks, and each gets a notification with their child\'s result.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(missing > 0 ? 'Go back' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: missing > 0 ? AppColors.statHomeworkText : AppColors.statusActiveText,
            ),
            child: Text(missing > 0 ? 'Publish anyway' : 'Publish'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _busy = true);
    final (notified, error) = await actions.publish(exam.id, allowIncomplete: missing > 0);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error, error: true);
    } else {
      _toast('Results published · $notified ${notified == 1 ? 'parent' : 'parents'} notified');
    }
  }

  Future<void> _unpublish(ExamModel exam) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Hide results from parents?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
          'Use this to correct a mistake. Teachers can edit marks again, and parents will not see results until you publish.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Unpublish')),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    final error = await ref.read(examActionsProvider).unpublish(exam.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ?? 'Results hidden. Marks can be corrected now.', error: error != null);
  }

  Future<void> _delete(ExamModel exam) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete ${exam.name}?', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
          'Only possible before any marks are entered.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusOverdueText),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    final error = await ref.read(examActionsProvider).deleteExam(exam.id);
    if (!mounted) return;
    if (error != null) {
      _toast(error, error: true);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _editPaper(ExamPaperModel paper) async {
    final maxController = TextEditingController(text: '${paper.maxMarks}');
    final passController = TextEditingController(text: '${paper.passMarks}');
    final saved = await showDialog<(int, int)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('${paper.subjectName} · ${paper.classroomName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: maxController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Maximum'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: passController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Pass'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final max = int.tryParse(maxController.text);
              final pass = int.tryParse(passController.text);
              if (max == null || pass == null) return;
              Navigator.pop(dialogContext, (max, pass));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    maxController.dispose();
    passController.dispose();
    if (saved == null || !mounted) return;
    final error = await ref
        .read(examActionsProvider)
        .updatePaper(paper.id, widget.examId, maxMarks: saved.$1, passMarks: saved.$2);
    if (!mounted) return;
    _toast(error ?? 'Paper updated', error: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.role.isAdmin ?? false;
    final examAsync = ref.watch(examDetailProvider(widget.examId));
    final papersAsync = ref.watch(examPapersProvider(widget.examId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          examAsync.value?.name ?? widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
        ),
        actions: [
          if (isAdmin && examAsync.value != null && !examAsync.value!.isPublished)
            IconButton(
              tooltip: 'Delete exam',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(examAsync.value!),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(examDetailProvider(widget.examId));
          ref.invalidate(examPapersProvider(widget.examId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            examAsync.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorStateView(message: friendlyError(ref, error)),
              data: (exam) => _Header(
                exam: exam,
                isAdmin: isAdmin,
                busy: _busy,
                onPublish: () => _publish(exam),
                onUnpublish: () => _unpublish(exam),
              ),
            ),
            const SizedBox(height: 18),
            papersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) => ErrorStateView(message: friendlyError(ref, error)),
              data: (papers) => _classSection(papers, isAdmin, examAsync.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _classSection(List<ExamPaperModel> papers, bool isAdmin, ExamModel? exam) {
    if (papers.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No papers for your classes',
        message: 'This exam has no subjects set for a class you teach.',
      );
    }

    final classes = <int, String>{};
    for (final paper in papers) {
      classes[paper.classroomId] = paper.classroomName;
    }
    final classId = classes.containsKey(_classId) ? _classId! : classes.keys.first;
    final classPapers = papers.where((p) => p.classroomId == classId).toList();
    final isPublished = exam?.isPublished ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (classes.length > 1) ...[
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final entry in classes.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: entry.key == classId,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: entry.key == classId ? AppColors.primary : AppColors.border),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: entry.key == classId ? Colors.white : AppColors.textSecondary,
                      ),
                      onSelected: (_) => setState(() => _classId = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                classes[classId]!,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClassResultsScreen(examId: widget.examId, classId: classId),
                ),
              ),
              icon: const Icon(Icons.leaderboard_outlined, size: 18),
              label: const Text('Results & ranks'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final paper in classPapers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PaperTile(
              paper: paper,
              isPublished: isPublished,
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MarkEntryScreen(paperId: paper.id, examId: widget.examId),
                ),
              ),
              onEdit: isAdmin && !isPublished ? () => _editPaper(paper) : null,
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.exam,
    required this.isAdmin,
    required this.busy,
    required this.onPublish,
    required this.onUnpublish,
  });

  final ExamModel exam;
  final bool isAdmin;
  final bool busy;
  final VoidCallback onPublish;
  final VoidCallback onUnpublish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: exam.isPublished ? AppColors.statusActiveBg : AppColors.primaryDark,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDateRange(exam.startDate, exam.endDate),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: exam.isPublished ? AppColors.statusActiveText : Colors.white70,
                  ),
                ),
              ),
              PublishStateChip(isPublished: exam.isPublished),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            exam.isPublished
                ? 'Parents can see these results.'
                : 'Marks are private to staff until the results are published.',
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: exam.isPublished ? AppColors.statusActiveText : Colors.white,
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: exam.isPublished
                  ? OutlinedButton.icon(
                      onPressed: busy ? null : onUnpublish,
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('Unpublish to correct marks'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusActiveText,
                        side: const BorderSide(color: AppColors.statusActiveBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: busy ? null : onPublish,
                      icon: busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_outlined, size: 18),
                      label: const Text('Publish results to parents'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({required this.paper, required this.isPublished, required this.onOpen, this.onEdit});

  final ExamPaperModel paper;
  final bool isPublished;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final entered = paper.enteredCount ?? 0;
    final canEnter = paper.canEnterMarks && !isPublished;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        onLongPress: onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paper.subjectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Out of ${paper.maxMarks} · pass ${paper.passMarks} · $entered entered',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Change marks',
                  icon: const Icon(Icons.tune_rounded, size: 20, color: AppColors.textSecondary),
                  onPressed: onEdit,
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: canEnter ? AppColors.primary : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  canEnter ? 'Enter marks' : 'View',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: canEnter ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
