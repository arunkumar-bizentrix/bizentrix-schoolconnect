import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../models/exam_models.dart';
import '../providers/exams_provider.dart';
import 'exams_screen.dart';

/// Marks for one subject in one class.
///
/// Built for a teacher entering forty marks in a row: the keyboard stays up
/// and "next" moves down the list, absent is one tap, and nothing is sent
/// until Save - so a slip of the thumb costs nothing.
class MarkEntryScreen extends ConsumerStatefulWidget {
  const MarkEntryScreen({super.key, required this.paperId, required this.examId});

  final int paperId;
  final int examId;

  @override
  ConsumerState<MarkEntryScreen> createState() => _MarkEntryScreenState();
}

class _MarkEntryScreenState extends ConsumerState<MarkEntryScreen> {
  List<MarkEntry>? _entries;
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focus = {};
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _adopt(MarkSheet sheet) {
    if (_entries != null) return;
    _entries = sheet.entries;
    for (final entry in sheet.entries) {
      _controllers[entry.studentId] = TextEditingController(
        text: entry.isAbsent || entry.marks == null ? '' : formatMarks(entry.marks),
      );
      _focus[entry.studentId] = FocusNode();
    }
  }

  String? _problem(MarkEntry entry, int maxMarks) {
    if (entry.isAbsent) return null;
    final text = _controllers[entry.studentId]!.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null) return 'Not a number';
    if (value < 0) return 'Cannot be negative';
    if (value > maxMarks) return 'Max $maxMarks';
    return null;
  }

  Future<void> _save(MarkSheet sheet) async {
    final entries = _entries!;
    for (final entry in entries) {
      if (_problem(entry, sheet.paper.maxMarks) != null) {
        _toast('Fix the highlighted marks before saving.', error: true);
        return;
      }
      final text = _controllers[entry.studentId]!.text.trim();
      entry.marks = entry.isAbsent || text.isEmpty ? null : double.parse(text);
    }

    setState(() => _saving = true);
    final error = await ref.read(examActionsProvider).saveMarks(sheet.paper.id, widget.examId, entries);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) _dirty = false;
    });
    _toast(error ?? 'Marks saved', error: error != null);
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.statusOverdueText : AppColors.statusActiveText,
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Leave without saving?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text('The marks you typed on this screen have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Stay')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusOverdueText),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final sheetAsync = ref.watch(markSheetProvider(widget.paperId));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: Text(
            sheetAsync.value == null
                ? 'Marks'
                : '${sheetAsync.value!.paper.subjectName} · ${sheetAsync.value!.paper.classroomName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
          ),
        ),
        body: sheetAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorStateView(
            message: friendlyError(ref, error),
            onRetry: () => ref.invalidate(markSheetProvider(widget.paperId)),
          ),
          data: (sheet) {
            _adopt(sheet);
            return _body(sheet);
          },
        ),
      ),
    );
  }

  Widget _body(MarkSheet sheet) {
    final entries = _entries!;
    final editable = sheet.paper.canEnterMarks && !sheet.isPublished;
    final entered = entries.where((e) => e.isAbsent || _controllers[e.studentId]!.text.trim().isNotEmpty).length;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sheet.examName} · out of ${sheet.paper.maxMarks}, pass ${sheet.paper.passMarks}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: entries.isEmpty ? 0 : entered / entries.length,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceElevated,
                  color: entered == entries.length ? AppColors.statusActiveText : AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$entered of ${entries.length} entered',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              if (!editable) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.statHomeworkBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 16, color: AppColors.statHomeworkText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sheet.isPublished
                              ? 'Results are published, so marks are locked. The admin can unpublish to correct them.'
                              : '${sheet.paper.subjectName} marks are entered by the teacher who teaches it.',
                          style: const TextStyle(fontSize: 12, color: AppColors.statHomeworkText, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(icon: Icons.people_outline, title: 'No students in this class')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _row(sheet, entries, index, editable),
                ),
        ),
        if (editable)
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || !_dirty ? null : () => _save(sheet),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_dirty ? 'Save marks' : 'All changes saved', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(MarkSheet sheet, List<MarkEntry> entries, int index, bool editable) {
    final entry = entries[index];
    final controller = _controllers[entry.studentId]!;
    final problem = _problem(entry, sheet.paper.maxMarks);
    final text = controller.text.trim();
    final value = double.tryParse(text);
    final belowPass = !entry.isAbsent && value != null && problem == null && value < sheet.paper.passMarks;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: problem != null ? AppColors.statusOverdueText : AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                Text(
                  problem ?? (belowPass ? 'Below pass mark' : entry.admissionNumber),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: problem != null
                        ? AppColors.statusOverdueText
                        : (belowPass ? AppColors.statHomeworkText : AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              controller: controller,
              focusNode: _focus[entry.studentId],
              enabled: editable && !entry.isAbsent,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: index == entries.length - 1 ? TextInputAction.done : TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d?)?'))],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
              decoration: InputDecoration(
                isDense: true,
                hintText: entry.isAbsent ? 'AB' : '-',
                filled: true,
                fillColor: entry.isAbsent ? AppColors.surfaceElevated : AppColors.background,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() => _dirty = true),
              onSubmitted: (_) {
                if (index < entries.length - 1) {
                  _focus[entries[index + 1].studentId]?.requestFocus();
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Absent',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: !editable
                  ? null
                  : () => setState(() {
                        entry.isAbsent = !entry.isAbsent;
                        if (entry.isAbsent) controller.clear();
                        _dirty = true;
                      }),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.isAbsent ? AppColors.statusOverdueBg : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'AB',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: entry.isAbsent ? AppColors.statusOverdueText : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
