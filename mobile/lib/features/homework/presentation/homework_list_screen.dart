import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/school_providers.dart';
import 'create_homework_screen.dart';

class HomeworkListScreen extends ConsumerStatefulWidget {
  const HomeworkListScreen({super.key});

  @override
  ConsumerState<HomeworkListScreen> createState() => _HomeworkListScreenState();
}

class _HomeworkListScreenState extends ConsumerState<HomeworkListScreen> {
  String _selectedTab = 'All';
  final List<String> _tabs = ['All', 'Upcoming', 'Overdue'];

  @override
  Widget build(BuildContext context) {
    final homeworkAsync = ref.watch(homeworkProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Add Homework Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Homework',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Create and manage homework assignments',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateHomeworkScreen()),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Homework', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filter Tabs (All, Upcoming, Overdue)
          Row(
            children: _tabs.map((tab) {
              final isSelected = _selectedTab == tab;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(tab),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedTab = tab),
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Homework List
          homeworkAsync.when(
            data: (list) {
              final filtered = list.where((item) {
                if (_selectedTab == 'Upcoming') return !item.isOverdue;
                if (_selectedTab == 'Overdue') return item.isOverdue;
                return true;
              }).toList();

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _buildHomeworkCard(item, index);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error loading homework: $err'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHomeworkCard(item, int index) {
    Color iconBg;
    Color iconColor;
    IconData iconData;

    final sub = item.subject.toLowerCase();
    if (sub.contains('math')) {
      iconBg = index == 0 ? AppColors.mathIconBg : AppColors.defaultIconBg;
      iconColor = index == 0 ? AppColors.mathIconColor : AppColors.defaultIconColor;
      iconData = Icons.calculate_outlined;
    } else if (sub.contains('sci')) {
      iconBg = AppColors.scienceIconBg;
      iconColor = AppColors.scienceIconColor;
      iconData = Icons.eco_outlined;
    } else if (sub.contains('eng')) {
      iconBg = AppColors.englishIconBg;
      iconColor = AppColors.englishIconColor;
      iconData = Icons.menu_book_outlined;
    } else {
      iconBg = AppColors.socialIconBg;
      iconColor = AppColors.socialIconColor;
      iconData = Icons.public_outlined;
    }

    final formattedDate = DateFormat('MMM dd, yyyy').format(item.dueDate);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject Icon Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconData, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),

          // Homework Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (item.isOverdue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.statusOverdueBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Overdue',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.statusOverdueText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.classroomName,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Due: $formattedDate',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          // Three Dots Action Menu
          IconButton(
            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
