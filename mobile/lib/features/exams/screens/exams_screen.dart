import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/role_access.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/exam_models.dart';
import '../providers/exams_provider.dart';
import 'create_exam_screen.dart';
import 'exam_detail_screen.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDay(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

String formatDateRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Dates not set';
  if (end == null || end == start) return formatDay(start);
  if (start.year == end.year && start.month == end.month) {
    return '${start.day} - ${end.day} ${_months[end.month - 1]} ${end.year}';
  }
  return '${formatDay(start)} - ${formatDay(end)}';
}

/// Exams for staff: the admin sets them up and publishes results; teachers
/// open them to enter marks for their subjects.
class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authProvider).user?.role.isAdmin ?? false;
    final examsAsync = ref.watch(examsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          isAdmin ? 'Exams & Results' : 'Exams & Marks',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New exam'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateExamScreen()),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(examsProvider),
        child: examsAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [
            ErrorStateView(
              message: friendlyError(ref, error),
              onRetry: () => ref.invalidate(examsProvider),
            ),
          ]),
          data: (exams) {
            if (exams.isEmpty) {
              return ListView(children: [
                EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No exams yet',
                  message: isAdmin
                      ? 'Create an exam, choose the classes and subjects, and teachers can start entering marks.'
                      : 'When the office sets up an exam for your classes, it appears here for marks entry.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: exams.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _ExamCard(exam: exams[index]),
            );
          },
        ),
      ),
    );
  }
}

/// Provider errors are usually DioExceptions; show the server's explanation
/// ("You can only see results for classes you teach.") rather than a dump.
String friendlyError(WidgetRef ref, Object error) =>
    ref.read(apiClientProvider).handleError(error).message;

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});

  final ExamModel exam;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ExamDetailScreen(examId: exam.id, title: exam.name)),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      exam.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PublishStateChip(isPublished: exam.isPublished),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${formatDateRange(exam.startDate, exam.endDate)} · ${exam.academicYear}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _Fact(icon: Icons.meeting_room_outlined, text: '${exam.classrooms.length} ${exam.classrooms.length == 1 ? 'class' : 'classes'}'),
                  _Fact(icon: Icons.menu_book_outlined, text: '${exam.subjects.length} ${exam.subjects.length == 1 ? 'subject' : 'subjects'}'),
                ],
              ),
              if (exam.subjects.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  exam.subjects.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Draft / Published badge. Encodes the one state that matters to everyone:
/// can parents see this yet?
class PublishStateChip extends StatelessWidget {
  const PublishStateChip({super.key, required this.isPublished});

  final bool isPublished;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isPublished ? AppColors.statusActiveBg : AppColors.statHomeworkBg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublished ? Icons.visibility_outlined : Icons.edit_note_outlined,
            size: 13,
            color: isPublished ? AppColors.statusActiveText : AppColors.statHomeworkText,
          ),
          const SizedBox(width: 4),
          Text(
            isPublished ? 'Published' : 'Draft',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isPublished ? AppColors.statusActiveText : AppColors.statHomeworkText,
            ),
          ),
        ],
      ),
    );
  }
}
