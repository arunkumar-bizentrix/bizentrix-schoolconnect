import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/role_access.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/classes_provider.dart';
import '../providers/homework_provider.dart';
import '../../students/providers/students_provider.dart';

class CreateHomeworkScreen extends ConsumerStatefulWidget {
  const CreateHomeworkScreen({super.key});

  @override
  ConsumerState<CreateHomeworkScreen> createState() => _CreateHomeworkScreenState();
}

class _CreateHomeworkScreenState extends ConsumerState<CreateHomeworkScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedClassId;
  bool _assignToIndividual = false;
  int? _selectedStudentId;
  String _selectedSubject = 'Mathematics';
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 3));
  // Optional clock deadline. Null means "due that day", which is how most
  // homework works - the teacher opts in to a time.
  TimeOfDay? _dueTime;
  PlatformFile? _pickedAttachment;
  bool _isSubmitting = false;

  final List<String> _subjects = [
    'Mathematics',
    'Science',
    'English',
    'Social Science',
    'Computer Science',
    'Hindi',
    'Tamil',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedAttachment = result.files.first);
    }
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDueDate() =>
      '${_dueDate.day} ${_monthNames[_dueDate.month - 1]} ${_dueDate.year}';

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a class'),
          backgroundColor: AppColors.statusOverdueText,
        ),
      );
      return;
    }

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (_dueDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Due date cannot be in the past. Please select today or a future date.'),
          backgroundColor: AppColors.statusOverdueText,
        ),
      );
      return;
    }

    if (_assignToIndividual && _selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an individual student from the list'),
          backgroundColor: AppColors.statusOverdueText,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final error = await ref.read(homeworkProvider.notifier).createHomework(
      classId: _selectedClassId!,
      studentId: _assignToIndividual ? _selectedStudentId : null,
      subject: _selectedSubject,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      dueDate: _dueDate,
      dueTime: _dueTime,
      attachmentFilePath: _pickedAttachment?.path,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _assignToIndividual
                ? 'Targeted homework created for student!'
                : 'Homework created successfully!',
          ),
          backgroundColor: AppColors.statusActiveText,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.statusOverdueText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final classes = classesAsync.value ?? [];
    final studentsAsync = ref.watch(studentsProvider);
    final allStudents = studentsAsync.value ?? [];

    if (_selectedClassId == null && classes.isNotEmpty) {
      _selectedClassId = classes.first.id;
    }

    final classStudents = allStudents.where((s) => s.classId == _selectedClassId).toList();

    // A teacher the admin has not put in charge of any class has nothing to
    // assign homework to. Showing an empty dropdown leaves them guessing at a
    // permission problem; say plainly whose job it is to fix.
    if (classesAsync.hasValue && classes.isEmpty) {
      return _noClassesYet(ref.watch(authProvider).user?.role.isAdmin ?? false);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Homework',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Class Dropdown
              _buildLabel('Class *'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: _fieldBoxDecoration(),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: classes.any((c) => c.id == _selectedClassId)
                        ? _selectedClassId
                        : (classes.isNotEmpty ? classes.first.id : null),
                    isExpanded: true,
                    hint: const Text('Select a class', style: TextStyle(fontSize: 14)),
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                    items: classes.map((cls) {
                      return DropdownMenuItem<int>(
                        value: cls.id,
                        child: Text(cls.name, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedClassId = val;
                          _selectedStudentId = null;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Assign Target (Entire Class vs Specific Student)
              _buildLabel('Assign To *'),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _assignToIndividual = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_assignToIndividual ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: !_assignToIndividual
                                ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.groups_rounded,
                                size: 16,
                                color: !_assignToIndividual ? AppColors.primary : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                'Entire Class',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: !_assignToIndividual ? AppColors.primary : AppColors.textSecondary,
                                ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _assignToIndividual = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _assignToIndividual ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _assignToIndividual
                                ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: _assignToIndividual ? AppColors.primary : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                'Specific Student',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _assignToIndividual ? AppColors.primary : AppColors.textSecondary,
                                ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Student Dropdown (shown only when Specific Student is chosen)
              if (_assignToIndividual) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildLabel('Select Student *'),
                    Text(
                      '${classStudents.length} enrolled',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: _fieldBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: classStudents.any((s) => s.id == _selectedStudentId)
                          ? _selectedStudentId
                          : null,
                      isExpanded: true,
                      hint: Text(
                        classStudents.isEmpty
                            ? 'No students enrolled in this class'
                            : 'Choose student',
                        style: const TextStyle(fontSize: 14),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                      items: classStudents.map((stu) {
                        return DropdownMenuItem<int>(
                          value: stu.id,
                          child: Text(
                            '${stu.fullName} (${stu.admissionNumber})',
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: classStudents.isEmpty
                          ? null
                          : (val) {
                              if (val != null) setState(() => _selectedStudentId = val);
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Subject Dropdown
              _buildLabel('Subject *'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: _fieldBoxDecoration(),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSubject,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                    items: _subjects.map((sub) {
                      return DropdownMenuItem(value: sub, child: Text(sub, style: const TextStyle(fontSize: 14)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedSubject = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title Input
              _buildLabel('Title *'),
              TextFormField(
                controller: _titleController,
                validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
                decoration: _inputDecoration('Enter homework title'),
              ),
              const SizedBox(height: 18),

              // Description Textarea
              _buildLabel('Description *'),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                validator: (val) => val == null || val.trim().isEmpty ? 'Description is required' : null,
                decoration: _inputDecoration('Provide homework instructions or exercise numbers...'),
              ),
              const SizedBox(height: 18),

              // Deadline: date is required, time is optional.
              _buildLabel('Due Date *'),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: _fieldBoxDecoration(),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _formatDueDate(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _buildLabel('Due Time (Optional)'),
              InkWell(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _dueTime ?? const TimeOfDay(hour: 16, minute: 0),
                  );
                  if (picked != null) setState(() => _dueTime = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: _fieldBoxDecoration(),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _dueTime == null
                              ? 'No specific time — due any time that day'
                              : _dueTime!.format(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: _dueTime == null
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (_dueTime != null)
                        GestureDetector(
                          onTap: () => setState(() => _dueTime = null),
                          child: const Icon(Icons.close_rounded,
                              size: 18, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Attachment Dropzone (Dashed border)
              _buildLabel('Attachment (Optional)'),
              InkWell(
                onTap: _pickAttachment,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primaryLight.withValues(alpha: 0.5),
                      width: 1.5,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _pickedAttachment != null ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                        size: 36,
                        color: _pickedAttachment != null ? AppColors.statusActiveText : AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pickedAttachment != null ? _pickedAttachment!.name : 'Tap to upload',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pickedAttachment != null
                            ? '${(_pickedAttachment!.size / (1024 * 1024)).toStringAsFixed(1)} MB'
                            : 'PDF, JPG, PNG (Max 10MB)',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Full Width Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                    shadowColor: AppColors.primary.withValues(alpha: 0.4),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: Text(
                    _isSubmitting ? 'Creating Homework...' : 'Create Homework',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown when there is no class to assign homework to.
  Widget _noClassesYet(bool isAdmin) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Homework',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.statClassesBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.class_outlined,
                    size: 30, color: AppColors.statClassesText),
              ),
              const SizedBox(height: 18),
              const Text(
                'No class assigned to you yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAdmin
                    ? 'Create a class first, then come back to set homework '
                        'for it.'
                    : 'Homework is set for a class you teach. Ask the school '
                        'admin to add you to your class - it takes them a '
                        'moment, and everything here opens up straight away.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
    );
  }

  BoxDecoration _fieldBoxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
    );
  }
}
