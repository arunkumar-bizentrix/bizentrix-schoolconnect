import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
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
    final user = ref.watch(authProvider).user;
    final isParent = user?.role == UserRole.parent;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Title & Subtitle + Add Announcement Button (hidden for Parents)
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
              if (!isParent)
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

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.campaign_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'No announcements yet.',
                          style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notice = filtered[index];
                  return _buildAnnouncementCard(context, notice, isParent);
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
                    const SizedBox(height: 8),
                    Text(
                      'Error loading announcements: $err',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(announcementsProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(BuildContext context, AnnouncementModel notice, bool isParent) {
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
              color: Colors.black.withValues(alpha: 0.02),
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

            // 3-dots Menu (hidden for Parents)
            if (!isParent)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onSelected: (val) {
                  if (val == 'delete') {
                    _confirmDeleteAnnouncement(context, notice);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAnnouncement(BuildContext context, AnnouncementModel notice) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${notice.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ref.read(announcementsProvider.notifier).deleteAnnouncement(notice.id);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ok ? 'Announcement deleted successfully' : 'Failed to delete announcement'),
                  backgroundColor: ok ? AppColors.statusActiveText : AppColors.statusOverdueText,
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddAnnouncementDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final user = ref.read(authProvider).user;
    final isTeacher = user?.role == UserRole.teacher;
    String priority = 'NORMAL';
    String audience = isTeacher ? 'CLASS' : 'SCHOOL';
    int? selectedClassId;
    final formKey = GlobalKey<FormState>();
    final classes = ref.read(classesProvider).value ?? [];
    if (classes.isNotEmpty) {
      selectedClassId = classes.first.id;
    }

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
                  if (!isTeacher) ...[
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
                  if (audience == 'CLASS') ...[
                    const SizedBox(height: 10),
                    const Text('Target Class *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (classes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No classes assigned to you.',
                          style: TextStyle(fontSize: 12, color: AppColors.statusOverdueText),
                        ),
                      )
                    else
                      DropdownButtonFormField<int>(
                        initialValue: classes.any((c) => c.id == selectedClassId) ? selectedClassId : classes.first.id,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName))).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedClassId = val);
                        },
                      ),
                  ],
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
                final ok = await ref.read(announcementsProvider.notifier).createAnnouncement(
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  priority: priority,
                  audienceType: audience,
                  targetClassId: audience == 'CLASS' ? selectedClassId : null,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? '"${titleCtrl.text.trim()}" posted successfully! ✅' : 'Failed to post announcement.'),
                      backgroundColor: ok ? AppColors.statusActiveText : AppColors.statusOverdueText,
                    ),
                  );
                }
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}
