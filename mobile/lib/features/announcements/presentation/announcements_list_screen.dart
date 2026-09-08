import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/school_providers.dart';
import '../models/announcement_model.dart';
import 'announcement_detail_screen.dart';

class AnnouncementsListScreen extends ConsumerStatefulWidget {
  const AnnouncementsListScreen({super.key});

  @override
  ConsumerState<AnnouncementsListScreen> createState() => _AnnouncementsListScreenState();
}

class _AnnouncementsListScreenState extends ConsumerState<AnnouncementsListScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'School', 'Class'];

  @override
  Widget build(BuildContext context) {
    final announcementsAsync = ref.watch(announcementsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Title & Subtitle + Add Announcement Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Announcements',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'School circulars and notices',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddAnnouncementDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Announcement', style: TextStyle(fontSize: 12)),
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

          // Filter Chips: All, School, Class
          Row(
            children: _filters.map((filter) {
              final isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
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
          const SizedBox(height: 16),

          // Announcements List
          announcementsAsync.when(
            data: (items) {
              final filtered = items.where((item) {
                if (_selectedFilter == 'School') return item.audienceType == 'SCHOOL';
                if (_selectedFilter == 'Class') return item.audienceType == 'CLASS';
                return true;
              }).toList();

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notice = filtered[index];
                  return _buildAnnouncementCard(context, notice);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error loading announcements: $err'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(BuildContext context, AnnouncementModel notice) {
    Color iconBg;
    Color iconColor;
    IconData iconData;
    Color tagBg;
    Color tagText;

    if (notice.isUrgent) {
      iconBg = const Color(0xFFFEE2E2);
      iconColor = const Color(0xFFDC2626);
      iconData = Icons.description_outlined;
      tagBg = AppColors.priorityUrgentBg;
      tagText = AppColors.priorityUrgentText;
    } else if (notice.isImportant) {
      iconBg = const Color(0xFFEDE9FE);
      iconColor = const Color(0xFF7C3AED);
      iconData = Icons.description_outlined;
      tagBg = AppColors.priorityImportantBg;
      tagText = AppColors.priorityImportantText;
    } else if (notice.title.contains('Meeting')) {
      iconBg = const Color(0xFFDBEAFE);
      iconColor = const Color(0xFF2563EB);
      iconData = Icons.campaign_outlined;
      tagBg = AppColors.priorityNormalBg;
      tagText = AppColors.priorityNormalText;
    } else {
      iconBg = const Color(0xFFDBEAFE);
      iconColor = const Color(0xFF2563EB);
      iconData = Icons.description_outlined;
      tagBg = AppColors.priorityNormalBg;
      tagText = AppColors.priorityNormalText;
    }

    final formattedDate = DateFormat('MMM dd, yyyy').format(notice.publishedAt);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnnouncementDetailScreen(announcement: notice),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
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
            // Left Icon Square Container
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

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tagBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          notice.priority.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: tagText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notice.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notice.audienceLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Published: $formattedDate',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // 3-dots Menu
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  void _showAddAnnouncementDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String priority = 'NORMAL';
    String audience = 'SCHOOL';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Post Announcement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Enter announcement title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contentCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message *',
                      hintText: 'Enter announcement details...',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Message is required' : null,
                  ),
                  const SizedBox(height: 14),
                  const Text('Priority', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                      DropdownMenuItem(value: 'IMPORTANT', child: Text('Important')),
                      DropdownMenuItem(value: 'URGENT', child: Text('Urgent')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => priority = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text('Audience', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: audience,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'SCHOOL', child: Text('All School')),
                      DropdownMenuItem(value: 'CLASS', child: Text('Specific Class')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => audience = val);
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
                final existing = ref.read(announcementsProvider).value ?? [];
                final newId = existing.isEmpty ? 1 : existing.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;
                final newAnnouncement = AnnouncementModel(
                  id: newId,
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  priority: priority,
                  audienceType: audience,
                  createdByName: 'Priya Sharma (Teacher)',
                  publishedAt: DateTime.now(),
                );
                ref.read(announcementsProvider.notifier).addAnnouncement(newAnnouncement);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${titleCtrl.text.trim()}" posted successfully! ✅'),
                    backgroundColor: AppColors.statusActiveText,
                  ),
                );
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}
