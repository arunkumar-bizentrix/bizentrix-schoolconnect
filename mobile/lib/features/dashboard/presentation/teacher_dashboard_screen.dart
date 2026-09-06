import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Portal'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/homework'),
        backgroundColor: AppColors.roleTeacher,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Post Homework', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Teacher Welcome Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.roleTeacher, Color(0xFF0369A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Welcome, Mrs. Sharma',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Mathematics Dept',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Active Classes: 6-A, 6-B, 8-C',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Today's Stats
            Text("Today's Overview", style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildSummaryTile('Active Homework', '3', AppColors.primary),
                const SizedBox(width: 12),
                _buildSummaryTile('Submissions', '78', AppColors.roleParent),
                const SizedBox(width: 12),
                _buildSummaryTile('Announcements', '2', AppColors.accent),
              ],
            ),
            const SizedBox(height: 24),

            // Assigned Classes
            Text('My Classes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildClassCard(
              className: 'Class 6-A (Mathematics)',
              studentCount: 38,
              lastHomework: 'Algebra Exercise 4.2 - Due Tomorrow',
              context: context,
            ),
            const SizedBox(height: 10),
            _buildClassCard(
              className: 'Class 7-B (Mathematics)',
              studentCount: 36,
              lastHomework: 'Geometry Theorem Practice - Due in 2 days',
              context: context,
            ),
            const SizedBox(height: 24),

            // Recent Announcements
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('School Notices', style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: () => context.push('/announcements'),
                  child: const Text('View All'),
                ),
              ],
            ),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFEF3C7),
                  child: Icon(Icons.campaign, color: AppColors.accent),
                ),
                title: const Text(
                  'Parent-Teacher Meeting Scheduled',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text('Saturday, 10:00 AM in Main Auditorium', style: TextStyle(fontSize: 12)),
                onTap: () => context.push('/announcements'),
              ),
            ),
            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String title, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard({
    required String className,
    required int studentCount,
    required String lastHomework,
    required BuildContext context,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(className, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Chip(
                  label: Text('$studentCount Students', style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.assignment_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lastHomework,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
