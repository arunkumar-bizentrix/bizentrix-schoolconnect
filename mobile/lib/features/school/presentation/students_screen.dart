import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/school_providers.dart';
import '../models/student_model.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  int? _selectedClassId;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(studentsProvider.notifier).loadStudents(
        classId: _selectedClassId,
        search: query.trim(),
      );
    });
  }

  void _onClassFilterSelected(int? classId) {
    setState(() => _selectedClassId = classId);
    ref.read(studentsProvider.notifier).loadStudents(
      classId: _selectedClassId,
      search: _searchController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsProvider);
    final classesAsync = ref.watch(classesProvider);
    final userRole = ref.watch(authProvider).role;
    final isParent = userRole == UserRole.parent;
    final isAdmin = userRole == UserRole.admin;
    final canManage = isAdmin || userRole == UserRole.teacher;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: canManage
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _showAddStudentDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(studentsProvider.notifier).loadStudents(
            classId: _selectedClassId,
            search: _searchController.text.trim(),
          );
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 80.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                isParent ? 'My Children' : 'Students',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isParent
                    ? 'Your registered wards at SchoolConnect'
                    : 'Manage your students',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Search Bar (Hidden for Parents)
              if (!isParent) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search by name or admission number...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                    setState(() {});
                                  },
                                )
                              : null,
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
                  ],
                ),
                const SizedBox(height: 14),

                // Dynamic Class Chips from Real Classes API
                classesAsync.when(
                  data: (classes) {
                    final allStudents = studentsAsync.value ?? [];
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: 'All (${allStudents.length})',
                            isSelected: _selectedClassId == null,
                            onTap: () => _onClassFilterSelected(null),
                          ),
                          ...classes.map((cls) {
                            final count = allStudents.where((s) => s.classId == cls.id).length;
                            return _buildFilterChip(
                              label: '${cls.displayName} ($count)',
                              isSelected: _selectedClassId == cls.id,
                              onTap: () => _onClassFilterSelected(cls.id),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
              ],

              // Students List
              studentsAsync.when(
                data: (students) {
                  if (students.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline, size: 40, color: AppColors.textMuted),
                          const SizedBox(height: 10),
                          Text(
                            isParent ? 'No registered wards found' : 'No students found',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isParent
                                ? 'Your registered wards will appear here.'
                                : isAdmin
                                    ? 'Try changing filters or tap "+" to enroll students.'
                                    : 'No students found in your assigned classes.',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return _buildStudentCard(context, ref, student, isParent, isAdmin);
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.priorityUrgentBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.priorityUrgentBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.priorityUrgentText, size: 30),
                      const SizedBox(height: 8),
                      Text(
                        err.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.priorityUrgentText, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(studentsProvider.notifier).loadStudents(),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.priorityUrgentText,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
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
  }

  Widget _buildStudentCard(
    BuildContext context,
    WidgetRef ref,
    StudentModel student,
    bool isParent,
    bool isAdmin,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Student Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE0F2FE),
            child: Icon(
              isParent ? Icons.child_care_rounded : Icons.person_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Student Details
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
                  'Adm No: ${student.admissionNumber}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Class: ${student.className} (${student.academicYear})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.statusActiveBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.statusActiveBorder),
            ),
            child: const Text(
              'ACTIVE',
              style: TextStyle(
                color: AppColors.statusActiveText,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Delete Action (Admin Only)
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.statusOverdueText),
              onPressed: () => _confirmDeleteStudent(context, ref, student),
              tooltip: 'Delete Student',
            ),
        ],
      ),
    );
  }

  void _showAddStudentDialog(BuildContext context, WidgetRef ref) {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final admCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final classes = ref.read(classesProvider).value ?? [];
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one class before enrolling students.')),
      );
      return;
    }

    int selectedClassId = classes.first.id;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add New Student', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: firstCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First Name *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: lastCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last Name *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: admCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Admission Number *', hintText: 'e.g. ADM010', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedClassId,
                    decoration: const InputDecoration(labelText: 'Class *', border: OutlineInputBorder()),
                    items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedClassId = val);
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
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final firstName = firstCtrl.text.trim();
                final lastName = lastCtrl.text.trim();
                final admNo = admCtrl.text.trim().toUpperCase();

                Navigator.pop(ctx);
                final err = await ref.read(studentsProvider.notifier).createStudent(
                  firstName: firstName,
                  lastName: lastName,
                  admissionNumber: admNo,
                  classEnrolled: selectedClassId,
                );

                if (!context.mounted) return;
                final success = err == null;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '$firstName $lastName enrolled successfully! ✅' : err),
                    backgroundColor: success ? AppColors.statusActiveText : AppColors.priorityUrgentText,
                  ),
                );
              },
              child: const Text('Enroll Student'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteStudent(BuildContext context, WidgetRef ref, StudentModel student) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Are you sure you want to remove ${student.fullName} (${student.admissionNumber})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusOverdueText, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await ref.read(studentsProvider.notifier).deleteStudent(student.id);
              if (!context.mounted) return;
              final success = err == null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Student removed.' : err),
                  backgroundColor: success ? AppColors.textPrimary : AppColors.priorityUrgentText,
                ),
              );
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
