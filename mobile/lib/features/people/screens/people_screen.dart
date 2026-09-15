import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../../shared/widgets/load_more_footer.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/models/staff_model.dart';
import '../providers/people_provider.dart';

/// The admin's register of teachers and parents.
///
/// Nobody signs up as a teacher: the admin adds them here and hands over a
/// one-time password. Parents mostly arrive through the roll-sheet import;
/// this is for the ones who were missed.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, this.initialRole = 'TEACHER'});

  final String initialRole;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialRole == 'PARENT' ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _role => _tabs.index == 0 ? 'TEACHER' : 'PARENT';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Teachers & Parents',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [Tab(text: 'Teachers'), Tab(text: 'Parents')],
        ),
      ),
      floatingActionButton: Consumer(
        builder: (context, ref, _) => FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: () => showPersonForm(context, ref, role: _role),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text(_role == 'TEACHER' ? 'Add teacher' : 'Add parent'),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _PeopleList(role: 'TEACHER'),
          _PeopleList(role: 'PARENT'),
        ],
      ),
    );
  }
}

class _PeopleList extends ConsumerWidget {
  const _PeopleList({required this.role});

  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(peopleProvider(role));
    final notifier = ref.read(peopleProvider(role).notifier);
    final isTeacher = role == 'TEACHER';

    return RefreshIndicator(
      onRefresh: () => notifier.load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          SearchField(
            hintText: isTeacher ? 'Search teachers by name or phone' : 'Search parents by name or phone',
            onSearch: (term) => notifier.load(search: term),
          ),
          const SizedBox(height: 12),
          ...peopleAsync.when(
            loading: () => const [LoadingView()],
            error: (error, _) => [ErrorStateView(message: '$error', onRetry: notifier.load)],
            data: (people) {
              if (people.isEmpty) {
                return [
                  EmptyState(
                    icon: isTeacher ? Icons.co_present_outlined : Icons.family_restroom_outlined,
                    title: isTeacher ? 'No teachers yet' : 'No parents found',
                    message: isTeacher
                        ? 'Add each teacher here. They sign in with their mobile number and the password you give them.'
                        : 'Parents come in with the roll-sheet import. Add anyone who was missed here.',
                  ),
                ];
              }
              return [
                for (final person in people)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PersonCard(person: person, onTap: () => _showActions(context, ref, person)),
                  ),
                LoadMoreFooter(
                  loadedCount: people.length,
                  totalCount: notifier.totalCount,
                  hasMore: notifier.hasMore,
                  isLoading: notifier.isLoadingMore,
                  onLoadMore: notifier.loadMore,
                  noun: isTeacher ? 'teachers' : 'parents',
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref, StaffModel person) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  person.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit details'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showPersonForm(context, ref, role: role, existing: person);
                },
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Reset password'),
                subtitle: const Text('Issues a new one-time password'),
                enabled: person.isActive,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirmed = await _confirm(
                    context,
                    title: 'Reset password?',
                    message: '${person.fullName} will need the new password to sign in. The old one stops working now.',
                    action: 'Reset',
                  );
                  if (!confirmed) return;
                  final result = await ref.read(peopleProvider(role).notifier).resetPassword(person);
                  if (!context.mounted) return;
                  if (result.isOk) {
                    await showLoginDetails(context, issued: result.value!, isNew: false);
                  } else {
                    _toast(context, result.error!, error: true);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  person.isActive ? Icons.person_off_outlined : Icons.person_outline,
                  color: person.isActive ? AppColors.statusOverdueText : AppColors.statusActiveText,
                ),
                title: Text(
                  person.isActive ? 'Deactivate' : 'Reactivate',
                  style: TextStyle(
                    color: person.isActive ? AppColors.statusOverdueText : AppColors.statusActiveText,
                  ),
                ),
                subtitle: Text(
                  person.isActive
                      ? 'Cannot sign in; their past records stay'
                      : 'Can sign in again with their password',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (person.isActive) {
                    final confirmed = await _confirm(
                      context,
                      title: 'Deactivate ${person.fullName}?',
                      message: person.isTeacher
                          ? 'They will be signed out and stop getting notifications. Homework and attendance they recorded stay.'
                          : 'They will be signed out and stop getting notifications about their children.',
                      action: 'Deactivate',
                      destructive: true,
                    );
                    if (!confirmed) return;
                  }
                  final result = await ref
                      .read(peopleProvider(role).notifier)
                      .update(person.id, isActive: !person.isActive);
                  if (!context.mounted) return;
                  _toast(
                    context,
                    result.isOk
                        ? (person.isActive ? '${person.fullName} deactivated' : '${person.fullName} reactivated')
                        : result.error!,
                    error: !result.isOk,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final StaffModel person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = !person.isActive;
    final unassigned = person.isActive && person.linked.isEmpty;

    return Material(
      color: muted ? AppColors.surfaceElevated : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                radius: 20,
                initials: person.initials,
                backgroundColor: muted
                    ? AppColors.border
                    : (person.isTeacher ? AppColors.statClassesBg : AppColors.statStudentsBg),
                foregroundColor: muted
                    ? AppColors.textMuted
                    : (person.isTeacher ? AppColors.statClassesText : AppColors.statStudentsText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            person.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: muted ? AppColors.textMuted : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (muted) const _Tag(label: 'Deactivated', color: AppColors.textMuted, background: AppColors.border),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      person.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    if (unassigned)
                      _Tag(
                        label: person.isTeacher ? 'Not assigned to a class yet' : 'No child linked yet',
                        color: AppColors.statHomeworkText,
                        background: AppColors.statHomeworkBg,
                        icon: Icons.info_outline,
                      )
                    else if (person.linked.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in person.linked.take(4))
                            _Tag(
                              label: label,
                              color: AppColors.textSecondary,
                              background: AppColors.surfaceElevated,
                            ),
                          if (person.linked.length > 4)
                            _Tag(
                              label: '+${person.linked.length - 4} more',
                              color: AppColors.textMuted,
                              background: AppColors.surfaceElevated,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.background, this.icon});

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// add / edit
// ---------------------------------------------------------------------------

/// Adds a teacher or parent, or edits one when [existing] is given.
Future<void> showPersonForm(
  BuildContext context,
  WidgetRef ref, {
  required String role,
  StaffModel? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _PersonForm(role: role, existing: existing, hostContext: context),
  );
}

class _PersonForm extends ConsumerStatefulWidget {
  const _PersonForm({required this.role, required this.hostContext, this.existing});

  final String role;
  final StaffModel? existing;
  final BuildContext hostContext;

  @override
  ConsumerState<_PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends ConsumerState<_PersonForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phoneNumber ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  bool _saving = false;
  String? _submitError;

  bool get _isTeacher => widget.role == 'TEACHER';
  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _submitError = null;
    });
    final notifier = ref.read(peopleProvider(widget.role).notifier);

    if (_isEdit) {
      final result = await notifier.update(
        widget.existing!.id,
        fullName: _name.text,
        phoneNumber: _phone.text,
        email: _email.text,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (!result.isOk) {
        setState(() => _submitError = result.error!);
        return;
      }
      Navigator.pop(context);
      if (widget.hostContext.mounted) _toast(widget.hostContext, 'Saved');
      return;
    }

    final result = await notifier.create(
      fullName: _name.text,
      phoneNumber: _phone.text,
      email: _email.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!result.isOk) {
      setState(() => _submitError = result.error!);
      return;
    }
    Navigator.pop(context);
    final issued = result.value!;
    if (widget.hostContext.mounted) {
      await showLoginDetails(widget.hostContext, issued: issued, isNew: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = _isTeacher ? 'teacher' : 'parent';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? 'Edit $noun' : 'Add $noun',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                _isEdit
                    ? 'Changing the mobile number changes how they sign in.'
                    : 'They sign in with this mobile number and a one-time password shown on the next screen.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Full name', Icons.person_outline),
                validator: (value) =>
                    (value == null || value.trim().length < 2) ? 'Enter the full name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: _decoration('Mobile number', Icons.phone_outlined),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  final local = digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
                  return local.length == 10 ? null : 'Enter a 10-digit mobile number';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoration('Email (optional)', Icons.alternate_email),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : 'Enter a valid email';
                },
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.priorityUrgentBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.priorityUrgentBorder),
                  ),
                  child: Text(
                    _submitError!,
                    style: const TextStyle(
                      color: AppColors.priorityUrgentText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Save changes' : 'Create account', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    );
  }
}

// ---------------------------------------------------------------------------
// login details
// ---------------------------------------------------------------------------

/// Tells the admin how the temporary password reaches the person.
///
/// Sent by SMS: say so, and show nothing secret. Not sent: show the password
/// this once, with a clear warning that it was not texted.
Future<void> showLoginDetails(
  BuildContext context, {
  required IssuedLogin issued,
  required bool isNew,
}) {
  final person = issued.account;
  final signInWith = person.phoneNumber.isNotEmpty ? person.phoneNumber : person.username;
  final password = issued.temporaryPassword;
  final expires = issued.expiresAt;
  final expiresText = expires == null
      ? ''
      : ' It works until ${expires.day}/${expires.month}/${expires.year}, and they must choose their own password when they sign in.';

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        issued.sentBySms
            ? (isNew ? 'Account created' : 'Password reset')
            : (isNew ? 'Account created' : 'New password issued'),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (issued.sentBySms) ...[
            Text(
              'A temporary password was sent by SMS to $signInWith.$expiresText',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.statHomeworkBg, borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sms_failed_outlined, size: 18, color: AppColors.statHomeworkText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not sent by SMS${issued.smsDetail == null ? '' : ' - ${issued.smsDetail}'} '
                      'Give these details to ${person.fullName} yourself. The password is shown only now.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.statHomeworkText, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _LoginLine(label: 'Login username', value: person.username),
            if (person.phoneNumber.isNotEmpty) ...[
              const SizedBox(height: 10),
              _LoginLine(label: 'Or mobile number', value: person.phoneNumber),
            ],
            const SizedBox(height: 10),
            _LoginLine(label: 'Temporary password', value: password ?? '-', emphasise: true),
            if (expiresText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(expiresText.trim(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
            ],
          ],
        ],
      ),
      actions: [
        if (!issued.sentBySms && password != null)
          TextButton.icon(
            onPressed: () async {
              final message = 'Vivekananda School app login\n'
                  'Name: ${person.fullName}\n'
                  'Username: ${person.username}\n'
                  '${person.phoneNumber.isEmpty ? '' : 'Mobile number: ${person.phoneNumber}\n'}'
                  'Temporary password: $password\n'
                  'You will be asked to choose your own password after signing in.';
              await Clipboard.setData(ClipboardData(text: message));
              if (dialogContext.mounted) _toast(dialogContext, 'Login details copied');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _LoginLine extends StatelessWidget {
  const _LoginLine({required this.label, required this.value, this.emphasise = false});

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: emphasise ? AppColors.statClassesBg : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: emphasise ? 22 : 15,
              fontWeight: FontWeight.w800,
              letterSpacing: emphasise ? 1.5 : 0,
              color: emphasise ? AppColors.statClassesText : AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.statusOverdueText : AppColors.primary,
          ),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.statusOverdueText : AppColors.statusActiveText,
    ),
  );
}
