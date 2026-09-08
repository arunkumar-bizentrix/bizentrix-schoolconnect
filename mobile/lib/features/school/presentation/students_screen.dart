import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/school_providers.dart';
import '../models/student_model.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  String _selectedClassFilter = 'All';
  final _searchController = TextEditingController();

  final List<Map<String, dynamic>> _filterChips = [
    {'label': 'All (48)', 'value': 'All'},
    {'label': 'Grade 5 - A (32)', 'value': 'Grade 5 - A'},
    {'label': 'Grade 6 - B (16)', 'value': 'Grade 6 - B'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsProvider);

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 80.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Students',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage your students',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar & Filter Button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by name or admission number...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Horizontal Filter Chips (All, Grade 5 - A, Grade 6 - B)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filterChips.map((chip) {
                  final isSelected = _selectedClassFilter == chip['value'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(chip['label']),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedClassFilter = chip['value']),
                      selectedColor: AppColors.primary,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : AppColors.border,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      showCheckmark: false,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),

            // Students List
            studentsAsync.when(
              data: (students) {
                final query = _searchController.text.trim().toLowerCase();
                final filtered = students.where((s) {
                  final matchesClass = _selectedClassFilter == 'All' || s.className.contains(_selectedClassFilter);
                  final matchesQuery = query.isEmpty ||
                      s.fullName.toLowerCase().contains(query) ||
                      s.admissionNumber.toLowerCase().contains(query);
                  return matchesClass && matchesQuery;
                }).toList();

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final student = filtered[index];
                    return _buildStudentCard(student);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Error loading students: $err'),
            ),
            const SizedBox(height: 70),
          ],
        ),
      ),
      Positioned(
        bottom: 16,
        right: 16,
        child: FloatingActionButton.extended(
          onPressed: () => _showAddStudentDialog(context),
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add, color: Colors.white, size: 18),
          label: const Text(
            'Add Student',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          elevation: 3,
        ),
      ),
    ],
  );
}

  Widget _buildStudentCard(student) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Student Avatar
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.statClassesBg,
            child: const Icon(Icons.person, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),

          // Student Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  student.admissionNumber,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  student.className,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // Active Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.statusActiveBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                color: AppColors.statusActiveText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddStudentDialog(BuildContext context) {
    final fnCtrl = TextEditingController();
    final lnCtrl = TextEditingController();
    final admCtrl = TextEditingController();
    String selectedClass = 'Grade 5 - A';
    final formKey = GlobalKey<FormState>();

    // Auto-suggest admission number
    final existingStudents = ref.read(studentsProvider).value ?? [];
    final nextNum = existingStudents.length + 1;
    admCtrl.text = 'ADM${nextNum.toString().padLeft(3, '0')}';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Student', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: fnCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: lnCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: admCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Admission Number *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedClass,
                    decoration: const InputDecoration(
                      labelText: 'Class *',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Grade 5 - A', child: Text('Grade 5 - A')),
                      DropdownMenuItem(value: 'Grade 6 - B', child: Text('Grade 6 - B')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedClass = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final firstName = fnCtrl.text.trim();
                final lastName = lnCtrl.text.trim();
                final fullName = '$firstName $lastName'.trim();
                final admNum = admCtrl.text.trim();
                final existing = ref.read(studentsProvider).value ?? [];
                final newId = existing.isEmpty ? 1 : existing.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
                final classId = selectedClass == 'Grade 5 - A' ? 1 : 2;
                final newStudent = StudentModel(
                  id: newId,
                  admissionNumber: admNum,
                  firstName: firstName,
                  lastName: lastName,
                  fullName: fullName,
                  classId: classId,
                  className: selectedClass,
                  isActive: true,
                );
                ref.read(studentsProvider.notifier).addStudent(newStudent);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$fullName registered successfully! ✅'),
                    backgroundColor: AppColors.statusActiveText,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
