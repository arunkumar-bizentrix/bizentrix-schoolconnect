import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  String _selectedChild = 'Aarav Sharma (Class 6-B)';
  final List<String> _children = [
    'Aarav Sharma (Class 6-B)',
    'Ananya Sharma (Class 2-A)',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/announcements'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.go('/login'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Child Selector Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(Icons.child_care_rounded, color: AppColors.roleParent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedChild,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down),
                        items: _children.map((child) {
                          return DropdownMenuItem<String>(
                            value: child,
                            child: Text(
                              child,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedChild = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Today's Homework Overview Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Today's Homework", style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: () => context.push('/homework'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildHomeworkItem(
              subject: 'Mathematics',
              title: 'Chapter 4: Linear Equations Exercise 4.2',
              dueDate: 'Tomorrow',
              hasAttachment: true,
              teacher: 'Mrs. Sharma',
              onTap: () => context.push('/homework'),
            ),
            const SizedBox(height: 10),
            _buildHomeworkItem(
              subject: 'English',
              title: 'Essay: The Role of Technology in Modern Education',
              dueDate: 'Thursday, Sept 10',
              hasAttachment: false,
              teacher: 'Mr. David',
              onTap: () => context.push('/homework'),
            ),
            const SizedBox(height: 24),

            // Announcements Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('School Circulars & Notices', style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: () => context.push('/announcements'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'URGENT',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Annual Sports Day Notice',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Annual sports trials will begin this coming Friday. Please ensure all student consent forms are signed.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Published 2 hours ago by Principal Office',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/announcements'),
                          icon: const Icon(Icons.attach_file, size: 14),
                          label: const Text('PDF Circular', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeworkItem({
    required String subject,
    required String title,
    required String dueDate,
    required bool hasAttachment,
    required String teacher,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                subject,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Due: $dueDate',
              style: const TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Assigned by $teacher',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (hasAttachment) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.attach_file, size: 14, color: AppColors.roleParent),
                  const Text(' Attachment', style: TextStyle(fontSize: 11, color: AppColors.roleParent)),
                ],
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
