import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/homework_model.dart';

class HomeworkListScreen extends StatefulWidget {
  const HomeworkListScreen({super.key});

  @override
  State<HomeworkListScreen> createState() => _HomeworkListScreenState();
}

class _HomeworkListScreenState extends State<HomeworkListScreen> {
  int _selectedTabIndex = 0;

  final List<HomeworkModel> _sampleHomework = [
    HomeworkModel(
      id: 'hw-1',
      title: 'Linear Equations Exercise 4.2',
      description: 'Solve questions 1 through 15 from Chapter 4 on graph paper. Ensure all steps are clearly shown.',
      subject: 'Mathematics',
      className: 'Class 6-B',
      dueDate: DateTime.now().add(const Duration(days: 1)),
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      teacherName: 'Mrs. Sharma',
      attachments: [
        const AttachmentModel(
          id: 'att-1',
          fileName: 'Exercise_4_2_Reference_Questions.pdf',
          fileUrl: 'https://example.com/files/math_hw.pdf',
          fileType: 'pdf',
          fileSize: 1048576,
        ),
      ],
    ),
    HomeworkModel(
      id: 'hw-2',
      title: 'Essay: The Role of Technology in Modern Education',
      description: 'Write a 300-word structured essay exploring both positive impacts and challenges of digital classrooms.',
      subject: 'English',
      className: 'Class 6-B',
      dueDate: DateTime.now().add(const Duration(days: 3)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      teacherName: 'Mr. David',
      attachments: [],
    ),
    HomeworkModel(
      id: 'hw-3',
      title: 'Photosynthesis Diagram and Lab Observations',
      description: 'Draw and label the plant chloroplast diagram. Write a summary of the sunlight absorption experiment.',
      subject: 'Science',
      className: 'Class 6-B',
      dueDate: DateTime.now().add(const Duration(days: 4)),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      teacherName: 'Ms. Anita',
      attachments: [
        const AttachmentModel(
          id: 'att-2',
          fileName: 'Chloroplast_Diagram_Sample.jpg',
          fileUrl: 'https://example.com/files/chloroplast.jpg',
          fileType: 'image',
          fileSize: 524288,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Homework Assignments'),
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildFilterChip('All Assignments', 0),
                const SizedBox(width: 8),
                _buildFilterChip('Due This Week', 1),
                const SizedBox(width: 8),
                _buildFilterChip('Completed', 2),
              ],
            ),
          ),
          const Divider(),

          // Homework List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _sampleHomework.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final hw = _sampleHomework[index];
                return _buildHomeworkCard(hw);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedTabIndex = index),
      selectedColor: AppColors.primary.withOpacity(0.15),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildHomeworkCard(HomeworkModel hw) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hw.subject,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  'Due: ${hw.dueDate.day}/${hw.dueDate.month}/${hw.dueDate.year}',
                  style: const TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              hw.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              hw.description,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_pin, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${hw.teacherName} • ${hw.className}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            if (hw.attachments.isNotEmpty) ...[
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                children: hw.attachments.map((attachment) {
                  final isPdf = attachment.fileType == 'pdf';
                  return ActionChip(
                    avatar: Icon(
                      isPdf ? Icons.picture_as_pdf : Icons.image,
                      size: 16,
                      color: isPdf ? AppColors.error : AppColors.secondary,
                    ),
                    label: Text(
                      attachment.fileName,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      _showAttachmentDialog(attachment);
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAttachmentDialog(AttachmentModel attachment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              attachment.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image,
              color: attachment.fileType == 'pdf' ? AppColors.error : AppColors.secondary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Attachment Preview',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File Name: ${attachment.fileName}'),
            const SizedBox(height: 8),
            Text('File Type: ${attachment.fileType.toUpperCase()}'),
            const SizedBox(height: 16),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.file_present_rounded, size: 40, color: AppColors.primary),
                    SizedBox(height: 8),
                    Text('Secure Document Viewer', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening ${attachment.fileName}...')),
              );
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download / Open'),
          ),
        ],
      ),
    );
  }
}
