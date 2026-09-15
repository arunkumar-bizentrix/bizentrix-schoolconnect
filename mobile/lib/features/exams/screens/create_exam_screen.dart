import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../classes/providers/class_options_provider.dart';
import '../../timetable/providers/timetable_editor_provider.dart';
import '../providers/exams_provider.dart';
import 'exam_detail_screen.dart';
import 'exams_screen.dart';

/// Sets up an exam: its name and dates, which classes write it, which
/// subjects, and the common maximum and pass marks. One paper is created per
/// class and subject; individual papers can be adjusted afterwards.
class CreateExamScreen extends ConsumerStatefulWidget {
  const CreateExamScreen({super.key});

  @override
  ConsumerState<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends ConsumerState<CreateExamScreen> {
  static const _commonNames = ['Unit Test 1', 'Unit Test 2', 'Quarterly Exam', 'Half Yearly Exam', 'Annual Exam'];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _maxMarks = TextEditingController(text: '100');
  final _passMarks = TextEditingController(text: '33');

  /// The pass mark follows 33% of the maximum (grade D is a pass) until the
  /// admin types their own.
  bool _passEdited = false;
  String _academicYear = AppConstants.currentAcademicYear;
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<int> _classIds = {};
  final Set<int> _subjectIds = {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _maxMarks.dispose();
    _passMarks.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _startDate : _endDate) ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_classIds.isEmpty || _subjectIds.isEmpty) {
      _toast(_classIds.isEmpty ? 'Choose at least one class.' : 'Choose at least one subject.');
      return;
    }
    setState(() => _saving = true);
    final (examId, error) = await ref.read(examActionsProvider).createExam(
          name: _name.text,
          academicYear: _academicYear,
          startDate: _startDate,
          endDate: _endDate,
          classroomIds: _classIds.toList(),
          subjectIds: _subjectIds.toList(),
          maxMarks: int.parse(_maxMarks.text),
          passMarks: int.parse(_passMarks.text),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null || examId == null) {
      _toast(error ?? 'The exam could not be created.');
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ExamDetailScreen(examId: examId, title: _name.text.trim())),
    );
  }

  Future<void> _addSubject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('New subject'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Subject name', hintText: 'e.g. Tamil'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final error = await ref.read(timetableEditorProvider).addSubject(name);
    if (!mounted) return;
    if (error != null) _toast(error);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.statusOverdueText),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classOptionsProvider(_academicYear));
    final subjectsAsync = ref.watch(subjectsProvider);
    final paperCount = _classIds.length * _subjectIds.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('New exam', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    paperCount == 0 ? 'Create exam' : 'Create exam · $paperCount ${paperCount == 1 ? 'paper' : 'papers'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _Label('Exam name'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration(hint: 'e.g. Quarterly Exam'),
              validator: (value) => (value == null || value.trim().length < 2) ? 'Give the exam a name' : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in _commonNames)
                  ActionChip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    onPressed: () => setState(() => _name.text = name),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _Label('Academic year'),
            DropdownButtonFormField<String>(
              initialValue: _academicYear,
              decoration: _decoration(),
              items: [
                for (final year in AppConstants.academicYearOptions)
                  DropdownMenuItem(value: year, child: Text(year)),
              ],
              onChanged: (year) {
                if (year == null) return;
                setState(() {
                  _academicYear = year;
                  _classIds.clear();
                });
              },
            ),
            const SizedBox(height: 18),
            const _Label('Dates'),
            Row(
              children: [
                Expanded(child: _DateButton(label: 'Starts', date: _startDate, onTap: () => _pickDate(start: true))),
                const SizedBox(width: 10),
                Expanded(child: _DateButton(label: 'Ends', date: _endDate, onTap: () => _pickDate(start: false))),
              ],
            ),
            const SizedBox(height: 22),
            _SelectHeader(
              title: 'Classes',
              count: _classIds.length,
              onSelectAll: classesAsync.value == null
                  ? null
                  : () => setState(() {
                        final all = classesAsync.value!.map((c) => c.id).toSet();
                        if (_classIds.length == all.length) {
                          _classIds.clear();
                        } else {
                          _classIds
                            ..clear()
                            ..addAll(all);
                        }
                      }),
            ),
            classesAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Text(friendlyError(ref, error), style: const TextStyle(color: AppColors.statusOverdueText)),
              data: (classes) => classes.isEmpty
                  ? Text('No classes for $_academicYear yet.', style: const TextStyle(color: AppColors.textMuted))
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final item in classes)
                          FilterChip(
                            label: Text(item.displayName.replaceAll(' ($_academicYear)', '')),
                            selected: _classIds.contains(item.id),
                            showCheckmark: false,
                            selectedColor: AppColors.statClassesBg,
                            backgroundColor: Colors.white,
                            side: BorderSide(color: _classIds.contains(item.id) ? AppColors.statClassesText : AppColors.border),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _classIds.contains(item.id) ? AppColors.statClassesText : AppColors.textSecondary,
                            ),
                            onSelected: (on) => setState(() => on ? _classIds.add(item.id) : _classIds.remove(item.id)),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 22),
            _SelectHeader(
              title: 'Subjects',
              count: _subjectIds.length,
              onSelectAll: subjectsAsync.value == null
                  ? null
                  : () => setState(() {
                        final all = subjectsAsync.value!.where((s) => s.isActive).map((s) => s.id).toSet();
                        if (_subjectIds.length == all.length) {
                          _subjectIds.clear();
                        } else {
                          _subjectIds
                            ..clear()
                            ..addAll(all);
                        }
                      }),
            ),
            subjectsAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Text(friendlyError(ref, error), style: const TextStyle(color: AppColors.statusOverdueText)),
              data: (subjects) {
                final active = subjects.where((s) => s.isActive).toList();
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final subject in active)
                      FilterChip(
                        label: Text(subject.name),
                        selected: _subjectIds.contains(subject.id),
                        showCheckmark: false,
                        selectedColor: AppColors.statAnnouncementsBg,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: _subjectIds.contains(subject.id) ? AppColors.statAnnouncementsText : AppColors.border),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _subjectIds.contains(subject.id) ? AppColors.statAnnouncementsText : AppColors.textSecondary,
                        ),
                        onSelected: (on) => setState(() => on ? _subjectIds.add(subject.id) : _subjectIds.remove(subject.id)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16, color: AppColors.primary),
                      label: const Text('New subject', style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      onPressed: _addSubject,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            const _Label('Marks for every paper'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _maxMarks,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration(label: 'Maximum'),
                    onChanged: (value) {
                      final max = int.tryParse(value);
                      if (_passEdited || max == null) return;
                      _passMarks.text = '${(max * 33 / 100).ceil()}';
                    },
                    validator: (value) {
                      final max = int.tryParse(value ?? '');
                      return (max == null || max <= 0 || max > 999) ? 'Enter 1-999' : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _passMarks,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration(label: 'Pass'),
                    onChanged: (_) => _passEdited = true,
                    validator: (value) {
                      final pass = int.tryParse(value ?? '');
                      final max = int.tryParse(_maxMarks.text) ?? 0;
                      if (pass == null) return 'Enter a number';
                      return pass > max ? 'Above maximum' : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'A practical out of 50? Change that one paper after creating the exam.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({String? hint, String? label}) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }
}

class _SelectHeader extends StatelessWidget {
  const _SelectHeader({required this.title, required this.count, this.onSelectAll});

  final String title;
  final int count;
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 0 ? title : '$title · $count selected',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onSelectAll, child: const Text('All / none')),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    Text(
                      date == null ? 'Choose' : formatDay(date!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
