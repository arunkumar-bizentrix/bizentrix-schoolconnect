import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/files/protected_file.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/load_more_footer.dart';
import '../../../shared/widgets/info_row.dart';
import '../../../core/utils/role_access.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/homework_provider.dart';
import '../models/homework_model.dart';
import 'create_homework_screen.dart';

class HomeworkListScreen extends ConsumerStatefulWidget {
  const HomeworkListScreen({super.key});

  @override
  ConsumerState<HomeworkListScreen> createState() => _HomeworkListScreenState();
}

class _HomeworkListScreenState extends ConsumerState<HomeworkListScreen> {
  String _selectedTab = 'All';
  final List<String> _tabs = ['All', 'Upcoming', 'Overdue'];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final homeworkAsync = ref.watch(homeworkProvider);
    final user = ref.watch(authProvider).user;
    final canManage = user?.role.canManageHomework ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Teachers create homework; admins and parents monitor it read-only.
          ScreenHeader(
            title: 'Homework',
            subtitle: 'Assignments and coursework',
            action: canManage
                ? ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateHomeworkScreen()),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Homework', style: TextStyle(fontSize: 12)),
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
          const SizedBox(height: 14),

          // Search Input Field
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? colors.surfaceContainerHighest
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'Search homework by title, subject, class...',
                hintStyle: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, size: 20, color: colors.onSurfaceVariant),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Filter Tabs (All, Upcoming, Overdue)
          // Horizontally scrollable so the chips never overflow on small phones.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: _tabs.map((tab) {
              final isSelected = _selectedTab == tab;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(tab),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedTab = tab),
                  selectedColor: AppColors.primary,
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? colors.surfaceContainerHighest
                      : Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : colors.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  side: BorderSide(color: isSelected ? AppColors.primary : colors.outlineVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  showCheckmark: false,
                ),
              );
            }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Homework List
          homeworkAsync.when(
            data: (list) {
              final filtered = list.where((item) {
                if (_selectedTab == 'Upcoming') {
                  if (item.isOverdue) return false;
                } else if (_selectedTab == 'Overdue') {
                  if (!item.isOverdue) return false;
                }
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  final matchTitle = item.title.toLowerCase().contains(q);
                  final matchSubject = item.subject.toLowerCase().contains(q);
                  final matchClass = item.className.toLowerCase().contains(q);
                  if (!matchTitle && !matchSubject && !matchClass) return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.assignment_outlined, size: 48, color: colors.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'No homework available.',
                          style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant, fontWeight: FontWeight.w500),
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
                  final item = filtered[index];
                  return _buildHomeworkCard(item, index, !canManage);
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
                      'Error loading homework: $err',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(homeworkProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Paged list: the API returns 20 at a time, so the full set is only
          // reachable through this.
          Builder(
            builder: (context) {
              final notifier = ref.read(homeworkProvider.notifier);
              return LoadMoreFooter(
                loadedCount: homeworkAsync.value?.length ?? 0,
                totalCount: notifier.totalCount,
                hasMore: notifier.hasMore,
                isLoading: notifier.isLoadingMore,
                noun: 'homework items',
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
    );
  }

  Widget _buildHomeworkCard(HomeworkModel item, int index, bool isParent) {
    final colors = Theme.of(context).colorScheme;
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

    final formattedDate = item.dueDisplay.isNotEmpty
        ? item.dueDisplay
        : DateFormat('MMM dd, yyyy').format(item.dueDate);

    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? colors.surfaceContainer
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _showHomeworkDetailModal(context, item, isParent),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colors.onSurface,
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
                      item.className.isNotEmpty ? item.className : item.subject,
                      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: $formattedDate',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.onSurface),
                      ),
                    ],
                  ],
                ),
              ),

              // Action Menu (hidden for Parents)
              if (!isParent)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 18, color: colors.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showEditHomeworkDialog(context, item);
                    } else if (val == 'delete') {
                      _confirmDelete(context, item);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('Edit', style: TextStyle(color: colors.onSurface, fontSize: 13)),
                        ],
                      ),
                    ),
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
      ),
    );
  }

  void _confirmDelete(BuildContext context, HomeworkModel item) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Homework', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${item.title}"?'),
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
              final err = await ref.read(homeworkProvider.notifier).deleteHomework(item.id);
              final ok = err == null;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ok ? 'Homework deleted successfully' : err),
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

  void _showHomeworkDetailModal(BuildContext context, HomeworkModel item, bool isParent) {
    final colors = Theme.of(context).colorScheme;
    final formattedAssigned = DateFormat('MMM dd, yyyy').format(item.assignedDate);
    final formattedDue = item.dueDisplay.isNotEmpty
        ? item.dueDisplay
        : DateFormat('MMM dd, yyyy').format(item.dueDate);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
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
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.statClassesBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.subject.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (item.isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.statusOverdueBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OVERDUE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.statusOverdueText,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  children: [
                    InfoRow(icon: Icons.meeting_room_outlined, label: 'Class', value: item.className.isNotEmpty ? item.className : 'Assigned Class', valueFontSize: 12, spacing: 8),
                    Divider(height: 16, color: colors.outlineVariant),
                    InfoRow(icon: Icons.person_outline, label: 'Assigned By', value: item.assignedByName.isNotEmpty ? item.assignedByName : 'Teacher', valueFontSize: 12, spacing: 8),
                    Divider(height: 16, color: colors.outlineVariant),
                    InfoRow(icon: Icons.event_available, label: 'Assigned Date', value: formattedAssigned, valueFontSize: 12, spacing: 8),
                    Divider(height: 16, color: colors.outlineVariant),
                    InfoRow(icon: Icons.event_busy, label: 'Due', value: formattedDue, valueFontSize: 12, spacing: 8),
                  ],
                ),
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Instructions & Description',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  item.description,
                  style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant, height: 1.4),
                ),
              ],
              if (item.attachmentUrl != null && item.attachmentUrl!.isNotEmpty) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => openProtectedFile(
                    context,
                    url: item.attachmentUrl!,
                    fileName: item.attachmentName ?? 'homework-attachment',
                  ),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(
                    item.attachmentName == null ? 'Open Attachment' : 'Open ${item.attachmentName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (!isParent)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditHomeworkDialog(context, item);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDelete(context, item);
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }


  void _showEditHomeworkDialog(BuildContext context, HomeworkModel item) {
    final titleCtrl = TextEditingController(text: item.title);
    final descCtrl = TextEditingController(text: item.description);
    DateTime dueDate = item.dueDate;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Homework', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, size: 20, color: AppColors.primary),
                  title: Text(
                    'Due: ${DateFormat('MMM dd, yyyy').format(dueDate)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialEntryMode: DatePickerEntryMode.inputOnly,
                        helpText: 'Enter due date',
                      );
                      if (picked != null) {
                        setDialogState(() => dueDate = picked);
                      }
                    },
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final err = await ref.read(homeworkProvider.notifier).updateHomework(
                  item.id,
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  dueDate: dueDate,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                final ok = err == null;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Homework updated successfully! ✅' : err),
                    backgroundColor: ok ? AppColors.statusActiveText : AppColors.statusOverdueText,
                  ),
                );
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
