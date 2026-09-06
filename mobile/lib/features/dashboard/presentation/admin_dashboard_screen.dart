import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
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
            // School Banner Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.roleAdmin, Color(0xFF4C1D95)],
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
                        'Springfield Academy',
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
                          'Admin Portal',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Academic Session: 2026 - 2027',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Metric Summary Cards
            Text('Quick Metrics', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard(context, 'Total Students', '840', Icons.people_outline, AppColors.primary),
                const SizedBox(width: 12),
                _buildMetricCard(context, 'Classes', '24', Icons.meeting_room_outlined, AppColors.secondary),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard(context, 'Teachers', '42', Icons.badge_outlined, AppColors.roleTeacher),
                const SizedBox(width: 12),
                _buildMetricCard(context, 'Notices', '18', Icons.campaign_outlined, AppColors.accent),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Text('Administrative Actions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              icon: Icons.campaign_rounded,
              title: 'Broadcast Announcement',
              subtitle: 'Send instant notification to parents or teachers',
              color: AppColors.accent,
              onTap: () => context.push('/announcements'),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              context: context,
              icon: Icons.menu_book_rounded,
              title: 'Monitor Homework',
              subtitle: 'Review assignments and submissions across classes',
              color: AppColors.primary,
              onTap: () => context.push('/homework'),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              context: context,
              icon: Icons.person_add_alt_1_rounded,
              title: 'Student & Teacher Directory',
              subtitle: 'Manage enrollments and classroom assignments',
              color: AppColors.roleParent,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Directory management will connect to backend API.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String label,
    String count,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                count,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
