import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../providers/students_provider.dart';

/// Admin-only bulk onboarding.
///
/// A school already keeps its roll in a spreadsheet; typing 1000 students in
/// by hand is not a launch plan. This uploads that file, shows a dry-run
/// preview of exactly what will change, and only then commits.
class ImportRollSheet extends ConsumerStatefulWidget {
  const ImportRollSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ImportRollSheet(),
    );
  }

  @override
  ConsumerState<ImportRollSheet> createState() => _ImportRollSheetState();
}

class _ImportRollSheetState extends ConsumerState<ImportRollSheet> {
  PlatformFile? _file;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    setState(() {
      _file = picked.files.first;
      _preview = null;
      _result = null;
      _error = null;
    });
    await _run(dryRun: true);
  }

  Future<void> _run({required bool dryRun}) async {
    final file = _file;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      setState(() => _error = 'Could not read that file. Pick it again.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final summary = await ref.read(studentsProvider.notifier).importRoll(
            bytes: bytes,
            filename: file.name,
            academicYear: AppConstants.currentAcademicYear,
            dryRun: dryRun,
          );
      if (!mounted) return;
      setState(() {
        if (dryRun) {
          _preview = summary;
        } else {
          _result = summary;
        }
      });
    } catch (message) {
      if (!mounted) return;
      setState(() => _error = message.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Import student roll',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Upload the school roll as a CSV. Classes and parent accounts '
              'named in the file are created automatically for '
              '${AppConstants.currentAcademicYear}.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            _formatCard(),
            const SizedBox(height: 16),
            if (_result == null) _filePicker(),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _banner(
                icon: Icons.error_outline_rounded,
                color: AppColors.priorityUrgentText,
                background: AppColors.priorityUrgentBg,
                text: _error!,
              ),
            ],
            if (_preview != null && _result == null) ...[
              const SizedBox(height: 16),
              _summary(_preview!, isPreview: true),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _run(dryRun: false),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(_busy ? 'Importing…' : 'Confirm and import'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _summary(_result!, isPreview: false),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _formatCard() {
    const header =
        'admission_number,first_name,last_name,class_name,section,date_of_birth,parent_name,parent_phone,parent_email';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_outlined,
                  size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Columns',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: header));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Header row copied')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Copy', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            header,
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: AppColors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Only admission_number and first_name are required. A row with a '
            'parent_phone creates that parent and links them to the child.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _filePicker() {
    return InkWell(
      onTap: _busy ? null : _pickFile,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: _file == null ? AppColors.background : AppColors.statStudentsBg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: _file == null ? AppColors.border : AppColors.statStudentsText,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _file == null
                  ? Icons.upload_file_outlined
                  : Icons.description_rounded,
              size: 22,
              color: _file == null
                  ? AppColors.textSecondary
                  : AppColors.statStudentsText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _file?.name ?? 'Choose a CSV file',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _file == null
                      ? AppColors.textSecondary
                      : AppColors.statStudentsText,
                ),
              ),
            ),
            if (_busy)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> summary, {required bool isPreview}) {
    int value(String key) =>
        summary[key] is int ? summary[key] as int : int.tryParse('${summary[key]}') ?? 0;

    final errors = (summary['errors'] as List? ?? const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _banner(
          icon: isPreview
              ? Icons.fact_check_outlined
              : Icons.check_circle_outline_rounded,
          color: isPreview ? AppColors.primary : AppColors.statusActiveText,
          background:
              isPreview ? AppColors.priorityNormalBg : AppColors.statStudentsBg,
          text: isPreview
              ? 'Preview only — nothing has been saved yet.'
              : 'Import complete.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat('${value('rows_processed')}', 'rows read'),
            _stat('${value('students_created')}', 'students added'),
            if (value('students_updated') > 0)
              _stat('${value('students_updated')}', 'students updated'),
            _stat('${value('classes_created')}', 'classes created'),
            _stat('${value('parents_created')}', 'parents created'),
            _stat('${value('parents_linked')}', 'parents linked'),
          ],
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '${errors.length} row${errors.length == 1 ? '' : 's'} skipped',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.priorityUrgentText,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.priorityUrgentBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView(
              shrinkWrap: true,
              children: errors.map((raw) {
                final error = raw as Map;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Row ${error['row']}: ${error['message']}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.priorityUrgentText,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color background,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
