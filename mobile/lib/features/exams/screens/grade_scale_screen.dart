import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/role_access.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/exam_models.dart';
import '../providers/exams_provider.dart';
import '../widgets/grade_badge.dart';
import 'exams_screen.dart';

/// The school's grading scale. Everyone can read it; the admin edits it.
///
/// The app never computes a grade itself - it only shows and saves the scale.
/// Changing it regrades every result the next time it is opened, because
/// grades are calculated from marks on the server, not stored.
class GradeScaleScreen extends ConsumerStatefulWidget {
  const GradeScaleScreen({super.key});

  @override
  ConsumerState<GradeScaleScreen> createState() => _GradeScaleScreenState();
}

class _EditableBand {
  _EditableBand(GradeBand band)
      : label = TextEditingController(text: band.label),
        minimum = TextEditingController(text: formatMarks(band.minPercentage)),
        description = TextEditingController(text: band.description);

  final TextEditingController label;
  final TextEditingController minimum;
  final TextEditingController description;

  void dispose() {
    label.dispose();
    minimum.dispose();
    description.dispose();
  }
}

class _GradeScaleScreenState extends ConsumerState<GradeScaleScreen> {
  List<_EditableBand>? _editing;
  bool _saving = false;

  @override
  void dispose() {
    for (final band in _editing ?? const <_EditableBand>[]) {
      band.dispose();
    }
    super.dispose();
  }

  void _startEditing(GradeScale scale) {
    setState(() => _editing = [for (final band in scale.bands) _EditableBand(band)]);
  }

  Future<void> _save() async {
    final rows = _editing!;
    final bands = <GradeBand>[];
    for (final row in rows) {
      final minimum = double.tryParse(row.minimum.text.trim());
      if (row.label.text.trim().isEmpty || minimum == null) {
        _toast('Every grade needs a label and a starting percentage.', error: true);
        return;
      }
      bands.add(GradeBand(label: row.label.text.trim(), minPercentage: minimum, description: row.description.text.trim()));
    }
    bands.sort((a, b) => b.minPercentage.compareTo(a.minPercentage));

    setState(() => _saving = true);
    final error = await ref.read(examActionsProvider).saveGradeScale(bands);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _toast(error, error: true);
      return;
    }
    for (final row in rows) {
      row.dispose();
    }
    setState(() => _editing = null);
    _toast('Grading scale saved. Results are regraded from marks.');
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? AppColors.statusOverdueText : AppColors.statusActiveText),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.role.isAdmin ?? false;
    final scaleAsync = ref.watch(gradeScaleProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('Grading scale', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
        actions: [
          if (isAdmin && _editing == null && scaleAsync.hasValue)
            TextButton(onPressed: () => _startEditing(scaleAsync.value!), child: const Text('Edit')),
        ],
      ),
      bottomNavigationBar: _editing == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => setState(() => _editing = null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save scale'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: scaleAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(message: friendlyError(ref, error), onRetry: () => ref.invalidate(gradeScaleProvider)),
        data: (scale) => _editing == null ? _readOnly(scale) : _editor(),
      ),
    );
  }

  Widget _readOnly(GradeScale scale) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          scale.isDefault
              ? 'The school uses the standard scale. Each subject is graded on its own percentage, and the overall grade on the total percentage.'
              : 'Each subject is graded on its own percentage, and the overall grade on the total percentage.',
          style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < scale.bands.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 56, child: Align(alignment: Alignment.centerLeft, child: GradeBadge(grade: scale.bands[i].label, large: true))),
                      Expanded(
                        child: Text(
                          scale.bands[i].description.isEmpty ? scale.bands[i].label : scale.bands[i].description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      Text(
                        '${scale.rangeOf(i)}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _editor() {
    final rows = _editing!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text(
          'Give each grade the lowest percentage that earns it. One grade must start at 0.',
          style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: rows[i].label,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    decoration: const InputDecoration(labelText: 'Grade', counterText: '', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: rows[i].minimum,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?'))],
                    decoration: const InputDecoration(labelText: 'From %', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: rows[i].description,
                    decoration: const InputDecoration(labelText: 'Meaning', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove grade',
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.statusOverdueText),
                  onPressed: rows.length <= 1
                      ? null
                      : () => setState(() {
                            rows.removeAt(i).dispose();
                          }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => rows.add(_EditableBand(const GradeBand(label: '', minPercentage: 0)))),
            icon: const Icon(Icons.add),
            label: const Text('Add grade'),
          ),
        ),
      ],
    );
  }
}
