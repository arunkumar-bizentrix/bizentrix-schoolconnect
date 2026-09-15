import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/load_more_footer.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../core/utils/role_access.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/staff_provider.dart';
import '../providers/classes_provider.dart';
import '../models/class_model.dart';
import '../../students/screens/students_screen.dart';
import '../../homework/screens/homework_list_screen.dart';
import '../../announcements/screens/announcements_list_screen.dart';

class ClassesScreen extends ConsumerStatefulWidget {
  const ClassesScreen({super.key});

  @override
  ConsumerState<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends ConsumerState<ClassesScreen> {
  String _selectedYear = AppConstants.currentAcademicYear;
  String _search = '';
  String _selectedSection = 'All';

  final List<String> _years = AppConstants.academicYearOptions;
  final List<String> _sections = ['All', 'A', 'B', 'C'];

  void _onFilterChanged() {
    ref.read(classesProvider.notifier).loadClasses(
      academicYear: _selectedYear,
      section: _selectedSection == 'All' ? null : _selectedSection,
      search: _search,
    );
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final userRole = ref.watch(authProvider).role;
    final isParent = userRole.isParent;
    final isAdmin = userRole.isAdmin;
    // Classes are administrative records: teachers read the ones assigned to
    // them, they do not create, edit, delete or reassign them.
    final canManage = userRole.canManageClasses;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(classesProvider.notifier).loadClasses(
          academicYear: _selectedYear,
          section: _selectedSection == 'All' ? null : _selectedSection,
          search: _search,
        );
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(
              title: isAdmin || isParent ? 'Classes' : 'My Classes',
              subtitle: isAdmin
                  ? 'School class sections'
                  : isParent
                      ? 'Academic class sections'
                      : 'Classes assigned to you',
              action: canManage
                  ? ElevatedButton.icon(
                      onPressed: () => _showAddOrEditClassDialog(context, ref),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Class', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),

            SearchField(
              hintText: 'Search by class name or section…',
              onSearch: (term) {
                setState(() => _search = term);
                ref.read(classesProvider.notifier).loadClasses(
                      academicYear: _selectedYear,
                      section: _selectedSection == 'All' ? null : _selectedSection,
                      search: term,
                    );
              },
            ),
            const SizedBox(height: 14),

            // Filter Controls Row (Academic Year & Section)
            Row(
              children: [
                // Academic Year Filter
                Expanded(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedYear,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                      items: _years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedYear) {
                          setState(() => _selectedYear = val);
                          _onFilterChanged();
                        }
                      },
                    ),
                  ),
                  ),
                ),
                const SizedBox(width: 10),

                // Section Filter
                Expanded(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSection,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                      items: _sections.map((s) => DropdownMenuItem(value: s, child: Text('Section: $s'))).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedSection) {
                          setState(() => _selectedSection = val);
                          _onFilterChanged();
                        }
                      },
                    ),
                  ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Class Cards / State Display
            classesAsync.when(
              data: (classes) {
                if (classes.isEmpty) {
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
                        const Icon(Icons.meeting_room_outlined, size: 40, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        const Text(
                          'No classes found',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isParent
                              ? 'No classes scheduled for the selected filter.'
                              : isAdmin
                                  ? 'Tap "+ Add Class" above to add sections.'
                                  : 'You have not been added to a class yet. '
                                      'The school admin assigns classes to '
                                      'teachers - ask them and this list fills '
                                      'in straight away.',
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
                  itemCount: classes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = classes[index];
                    final isEven = index % 2 == 0;
                    final badgeBg = isEven ? AppColors.statClassesText : AppColors.statStudentsText;

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => _showClassActionSheet(context, item),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Circular Grade Badge (5A, 6B)
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    item.shortCode,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Class Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.displayName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.classTeacherName != null
                                          ? 'Class teacher: ${item.classTeacherName}'
                                          : 'Faculty: ${item.teacherName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.studentCount} Students • ${item.academicYear}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Action Buttons for Admin and Teacher
                              if (canManage) ...[
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                                  onPressed: () => _showAddOrEditClassDialog(context, ref, classToEdit: item),
                                  tooltip: 'Edit Class',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.statusOverdueText),
                                  onPressed: () => _confirmDeleteClass(context, ref, item),
                                  tooltip: 'Delete Class',
                                ),
                              ] else
                                const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
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
                      onPressed: () => ref.read(classesProvider.notifier).loadClasses(),
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

            // Paged list: the API returns 20 at a time, so the roll is only
            // fully reachable through this.
            Builder(
              builder: (context) {
                final notifier = ref.read(classesProvider.notifier);
                return LoadMoreFooter(
                  loadedCount: classesAsync.value?.length ?? 0,
                  totalCount: notifier.totalCount,
                  hasMore: notifier.hasMore,
                  isLoading: notifier.isLoadingMore,
                  noun: 'classes',
                  onLoadMore: () async {
                    await notifier.loadMore();
                    if (context.mounted) setState(() {});
                  },
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAddOrEditClassDialog(BuildContext context, WidgetRef ref, {ClassModel? classToEdit}) {
    final isEdit = classToEdit != null;
    final nameCtrl = TextEditingController(text: classToEdit?.name ?? '');
    final secCtrl = TextEditingController(text: classToEdit?.section ?? '');
    final yearCtrl = TextEditingController(text: classToEdit?.academicYear ?? _selectedYear);
    final formKey = GlobalKey<FormState>();
    final selectedTeacherIds = <int>{...?classToEdit?.teacherIds};
    int? classTeacherId = classToEdit?.classTeacherId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEdit ? 'Edit Class' : 'Add New Class',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: SingleChildScrollView(
          child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Class Name *',
                  hintText: 'e.g. Grade 7',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: secCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Section *',
                  hintText: 'e.g. A or B',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: yearCtrl,
                decoration: const InputDecoration(
                  labelText: 'Academic Year *',
                  hintText: 'e.g. 2025-2026',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(v.trim())) {
                    return 'Format must be YYYY-YYYY (e.g. 2025-2026)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Teacher assignment - admin only, and the backend enforces that
              // too. Teachers assigned here are the ones who may post homework
              // and class announcements for this class.
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Assigned Teachers',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Consumer(
                builder: (context, innerRef, _) {
                  final teachersAsync = innerRef.watch(teachersProvider);
                  return teachersAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    error: (err, _) => const Text(
                      'Could not load teachers. You can still save the class '
                      'and assign teachers later.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    data: (teachers) {
                      if (teachers.isEmpty) {
                        return const Text(
                          'No teacher accounts yet. Create teachers first, '
                          'then assign them here.',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        );
                      }
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: teachers.map((teacher) {
                            final selected = selectedTeacherIds.contains(teacher.id);
                            return CheckboxListTile(
                              dense: true,
                              value: selected,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                teacher.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                teacher.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  selectedTeacherIds.add(teacher.id);
                                } else {
                                  selectedTeacherIds.remove(teacher.id);
                                  if (classTeacherId == teacher.id) classTeacherId = null;
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 14),

              // One teacher owns the daily attendance. Chosen from the ticked
              // teachers so the class teacher always teaches the class.
              Consumer(
                builder: (context, innerRef, _) {
                  final teachers = innerRef.watch(teachersProvider).value ?? const [];
                  final candidates = teachers
                      .where((teacher) => selectedTeacherIds.contains(teacher.id))
                      .toList();
                  final value = candidates.any((t) => t.id == classTeacherId) ? classTeacherId : null;
                  return DropdownButtonFormField<int?>(
                    initialValue: value,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Class teacher',
                      helperText: candidates.isEmpty
                          ? 'Tick a teacher above first'
                          : 'Takes the daily attendance',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('None')),
                      for (final teacher in candidates)
                        DropdownMenuItem<int?>(
                          value: teacher.id,
                          child: Text(teacher.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: candidates.isEmpty
                        ? null
                        : (selected) => setDialogState(() => classTeacherId = selected),
                  );
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
              final name = nameCtrl.text.trim();
              final section = secCtrl.text.trim().toUpperCase();
              final academicYear = yearCtrl.text.trim();              String? err;
              if (isEdit) {
                err = await ref.read(classesProvider.notifier).updateClass(
                  classToEdit.id,
                  name: name,
                  section: section,
                  academicYear: academicYear,
                  teacherIds: selectedTeacherIds.toList(),
                  classTeacherId: classTeacherId,
                );
              } else {
                err = await ref.read(classesProvider.notifier).createClass(
                  name: name,
                  section: section,
                  academicYear: academicYear,
                  teacherIds: selectedTeacherIds.toList(),
                  classTeacherId: classTeacherId,
                );
              }

              if (!ctx.mounted) return;
              Navigator.pop(ctx);

              final success = err == null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success
                      ? (isEdit ? 'Class updated successfully! ✅' : 'Class added successfully! ✅')
                      : err),
                  backgroundColor: success ? AppColors.statusActiveText : AppColors.priorityUrgentText,
                ),
              );
            },
            child: Text(isEdit ? 'Save Changes' : 'Save Class'),
          ),
        ],
        ),
      ),
    );
  }

  void _confirmDeleteClass(BuildContext context, WidgetRef ref, ClassModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Class'),
        content: Text('Are you sure you want to delete ${item.displayName}? This will remove all associated records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusOverdueText, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await ref.read(classesProvider.notifier).deleteClass(item.id);
              if (!context.mounted) return;
              final success = err == null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Class deleted.' : err),
                  backgroundColor: success ? AppColors.textPrimary : AppColors.priorityUrgentText,
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showClassActionSheet(BuildContext context, ClassModel item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.statClassesBg,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        item.shortCode,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${item.studentCount} Students • Faculty: ${item.teacherName}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, color: AppColors.border),
              ListTile(
                leading: const Icon(Icons.people_outline, color: AppColors.primary),
                title: const Text('View Students', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Students enrolled in this class', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: AppColors.background,
                        appBar: AppBar(
                          title: Text('${item.displayName} Students', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          backgroundColor: Colors.white,
                          elevation: 0,
                          iconTheme: const IconThemeData(color: AppColors.textPrimary),
                        ),
                        body: const StudentsScreen(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment_outlined, color: Color(0xFF4F46E5)),
                title: const Text('View Class Homework', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Homework assigned to this class', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: AppColors.background,
                        appBar: AppBar(
                          title: Text('${item.displayName} Homework', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          backgroundColor: Colors.white,
                          elevation: 0,
                          iconTheme: const IconThemeData(color: AppColors.textPrimary),
                        ),
                        body: const HomeworkListScreen(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.campaign_outlined, color: AppColors.priorityImportantText),
                title: const Text('View Class Announcements', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Notices published for this class', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: AppColors.background,
                        appBar: AppBar(
                          title: Text('${item.displayName} Notices', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          backgroundColor: Colors.white,
                          elevation: 0,
                          iconTheme: const IconThemeData(color: AppColors.textPrimary),
                        ),
                        body: const AnnouncementsListScreen(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
