import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

/// Choose a new password.
///
/// [forced]: the user signed in with a temporary password from the school
/// office. The backend refuses every other request until this is done, so
/// there is no way back - only "sign out".
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});

  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await ref.read(authProvider.notifier).changePassword(
          currentPassword: _current.text,
          newPassword: _new.text,
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error != null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password changed'), backgroundColor: AppColors.statusActiveText),
    );
    if (widget.forced) {
      context.go('/dashboard');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: !widget.forced,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: Text(
            widget.forced ? 'Choose your password' : 'Change password',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
          ),
          actions: [
            if (widget.forced)
              TextButton(
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
                child: const Text('Sign out'),
              ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                if (widget.forced) ...[
                  Text(
                    'Welcome${user == null ? '' : ', ${user.fullName.split(' ').first}'}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You signed in with a temporary password from the school office. Choose your own password to continue.',
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 22),
                ],
                TextFormField(
                  controller: _current,
                  obscureText: _obscure,
                  decoration: _decoration(widget.forced ? 'Temporary password' : 'Current password'),
                  validator: (value) => (value == null || value.isEmpty) ? 'Enter the password you signed in with' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _new,
                  obscureText: _obscure,
                  decoration: _decoration('New password',
                      helper: 'At least 8 characters. Not all numbers, and not a common password.'),
                  validator: (value) {
                    if (value == null || value.length < 8) return 'Use at least 8 characters';
                    if (RegExp(r'^\d+$').hasMatch(value)) return 'Use letters as well as numbers';
                    if (value == _current.text) return 'Choose a different password';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration: _decoration('Confirm new password'),
                  validator: (value) => value != _new.text ? 'The passwords do not match' : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    label: Text(_obscure ? 'Show passwords' : 'Hide passwords'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.statusOverdueBg, borderRadius: BorderRadius.circular(10)),
                    child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.statusOverdueText)),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save password', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    );
  }
}
