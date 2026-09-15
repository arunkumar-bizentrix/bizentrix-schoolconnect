import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../announcements/providers/announcements_provider.dart';
import '../../classes/providers/classes_provider.dart';
import '../../homework/providers/homework_provider.dart';
import '../../students/providers/students_provider.dart';
import '../providers/auth_provider.dart';

/// Two ways in. Email OTP was removed: parents at this school use WhatsApp,
/// not email, and running two OTP systems doubled the code and the failure
/// modes for no benefit.
enum AuthMethod { password, whatsappOtp }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  AuthMethod _authMethod = AuthMethod.password;

  final _phoneController = TextEditingController();
  final _whatsappOtpController = TextEditingController();
  bool _whatsappOtpSent = false;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  Timer? _countdownTimer;
  int _remainingSeconds = 300;
  int _cooldownSeconds = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authProvider).isAuthenticated) {
        context.go('/dashboard');
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    _whatsappOtpController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ───────────────────────────── timers ─────────────────────────────

  void _startTimers() {
    _countdownTimer?.cancel();
    _remainingSeconds = 300;
    _cooldownSeconds = 60;
    _canResend = false;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) _remainingSeconds--;
        if (_cooldownSeconds > 0) {
          _cooldownSeconds--;
        } else {
          _canResend = true;
        }
        if (_remainingSeconds <= 0 && _cooldownSeconds <= 0) timer.cancel();
      });
    });
  }

  void _resetOtpFlow() {
    _countdownTimer?.cancel();
    setState(() {
      _whatsappOtpSent = false;
      _whatsappOtpController.clear();
      _remainingSeconds = 300;
      _cooldownSeconds = 60;
      _canResend = false;
    });
  }

  String _formatTimer(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ───────────────────────────── feedback ─────────────────────────────

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? AppColors.priorityUrgentText : AppColors.statusActiveText,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _goToDashboard() {
    ref.read(classesProvider.notifier).refresh();
    ref.read(studentsProvider.notifier).refresh();
    ref.read(homeworkProvider.notifier).refresh();
    ref.read(announcementsProvider.notifier).refresh();
    context.go('/dashboard');
  }

  // ───────────────────────────── actions ─────────────────────────────

  Future<void> _handlePasswordLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _toast('Enter your mobile number and password.', error: true);
      return;
    }

    final success =
        await ref.read(authProvider.notifier).login(username, password);
    if (!mounted) return;

    if (success) {
      _goToDashboard();
    } else {
      _toast(
        ref.read(authProvider).errorMessage ??
            'Login failed. Please check your credentials.',
        error: true,
      );
    }
  }

  Future<void> _handleSendWhatsAppOtp() async {
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length < 10) {
      _toast('Enter a valid 10-digit mobile number.', error: true);
      return;
    }

    final result = await ref.read(authProvider.notifier).sendWhatsAppOtp(phone);
    if (!mounted) return;

    final ok = result['success'] == true ||
        result['message'] != null ||
        result['status'] == 'success';

    if (ok) {
      setState(() => _whatsappOtpSent = true);
      _startTimers();
      _toast(result['message']?.toString() ?? 'Code sent on WhatsApp.');
    } else {
      _toast(
        result['detail']?.toString() ??
            result['error']?.toString() ??
            ref.read(authProvider).errorMessage ??
            'Could not send the code. Please try again.',
        error: true,
      );
    }
  }

  Future<void> _handleVerifyWhatsAppOtp() async {
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final otp = _whatsappOtpController.text.trim();

    if (otp.length != 6) {
      _toast('Enter the 6-digit code from WhatsApp.', error: true);
      return;
    }

    final success =
        await ref.read(authProvider.notifier).verifyWhatsAppOtp(phone, otp);
    if (!mounted) return;

    if (success) {
      _countdownTimer?.cancel();
      _goToDashboard();
    } else {
      _toast(
        ref.read(authProvider).errorMessage ?? 'Incorrect code. Try again.',
        error: true,
      );
    }
  }

  // ───────────────────────────── layout ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      // One scroll view for band + form, so the keyboard simply pushes the
      // whole screen up instead of squeezing the fields.
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _brandCap(context),
              _formBody(authState),
            ],
          ),
        ),
      ),
    );
  }

  /// Solid school-blue band, curved where it meets the form. No photograph:
  /// flat brand colour holds up on a cheap phone screen in daylight, which a
  /// darkened photo does not.
  Widget _brandCap(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(24, topInset + 34, 24, 34),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset(
                AppConstants.schoolLogoPath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.school_rounded,
                  size: 28,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            AppConstants.schoolName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '${AppConstants.schoolBranch} • SINCE 1999',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC3D7FB),
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formBody(AuthState authState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _whatsappOtpSent ? 'Verify your number' : 'Welcome back',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _whatsappOtpSent
                ? 'Enter the 6-digit code we sent on WhatsApp'
                : 'Sign in to continue to your school account',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (!_whatsappOtpSent) ...[
            _methodSwitcher(),
            const SizedBox(height: 20),
          ],
          if (_whatsappOtpSent)
            _otpStep(authState)
          else if (_authMethod == AuthMethod.password)
            _passwordStep(authState)
          else
            _phoneStep(authState),
          const SizedBox(height: 18),
          _registerLink(),
        ],
      ),
    );
  }

  /// Two-option segmented control: one control, not three loose buttons.
  Widget _methodSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _switcherTab(
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            method: AuthMethod.password,
          ),
          _switcherTab(
            label: 'WhatsApp',
            icon: Icons.chat_bubble_outline_rounded,
            method: AuthMethod.whatsappOtp,
          ),
        ],
      ),
    );
  }

  Widget _switcherTab({
    required String label,
    required IconData icon,
    required AuthMethod method,
  }) {
    final selected = _authMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _authMethod = method),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── steps ─────────────────────────────

  Widget _passwordStep(AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Mobile number or username'),
        TextField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          decoration: _fieldDecoration(
            hint: 'e.g. 98765 43210',
            icon: Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: 14),
        _fieldLabel('Password'),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handlePasswordLogin(),
          decoration: _fieldDecoration(
            hint: 'Your password',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
                color: AppColors.textMuted,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Sign in',
          loading: authState.isLoading,
          onPressed: _handlePasswordLogin,
        ),
      ],
    );
  }

  Widget _phoneStep(AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('WhatsApp number'),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleSendWhatsAppOtp(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: _fieldDecoration(
            hint: '10-digit mobile number',
            icon: Icons.phone_iphone_rounded,
            prefixText: '+91 ',
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Send code on WhatsApp',
          loading: authState.isLoading,
          onPressed: _handleSendWhatsAppOtp,
        ),
        const SizedBox(height: 10),
        const Text(
          'We will send a 6-digit code to this number.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _otpStep(AuthState authState) {
    final expired = _remainingSeconds <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.statStudentsBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.mark_chat_read_rounded,
                  size: 18, color: AppColors.statStudentsText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '+91 ${_phoneController.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.statStudentsText,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _resetOtpFlow,
                child: const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.statStudentsText,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _whatsappOtpController,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleVerifyWhatsAppOtp(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 12,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 12,
              color: AppColors.border,
            ),
            filled: true,
            fillColor: AppColors.surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                expired
                    ? 'Code expired'
                    : 'Expires in ${_formatTimer(_remainingSeconds)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: expired ? AppColors.error : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: GestureDetector(
                onTap: _canResend ? _handleSendWhatsAppOtp : null,
                child: Text(
                  _canResend ? 'Resend code' : 'Resend in ${_cooldownSeconds}s',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _canResend ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Verify and sign in',
          loading: authState.isLoading,
          onPressed: _handleVerifyWhatsAppOtp,
        ),
      ],
    );
  }

  Widget _registerLink() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            "Don't have an account? ",
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          GestureDetector(
            onTap: () => _showRegistrationSheet(context),
            child: const Text(
              'Create one',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── shared bits ─────────────────────────────

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
      prefixIcon: Icon(icon, size: 19, color: AppColors.textMuted),
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
      ),
    );
  }

  // ───────────────────────────── registration ─────────────────────────────

  /// Creates a real account through POST /auth/register/ and signs the user
  /// straight in. The previous sheet collected a name, email and role and then
  /// threw them away, sending only an OTP.
  void _showRegistrationSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: _phoneController.text);
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 22,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Create your account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'For parents of ${AppConstants.schoolFullName}',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.statClassesBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: AppColors.statClassesText),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'This is for parents. Teachers: your login is created by '
                          'the school office - ask them for your password.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.statClassesText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _fieldLabel('Full name'),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration(
                    hint: 'e.g. Ravi Kumar',
                    icon: Icons.badge_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('Mobile number'),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: _fieldDecoration(
                    hint: '10-digit mobile number',
                    icon: Icons.phone_iphone_rounded,
                    prefixText: '+91 ',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('Email (optional)'),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _fieldDecoration(
                    hint: 'name@example.com',
                    icon: Icons.alternate_email_rounded,
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('Password'),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: _fieldDecoration(
                    hint: 'At least 8 characters',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 19,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => setSheetState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final phone = phoneCtrl.text.trim();
                            final pass = passCtrl.text;

                            if (name.length < 2) {
                              _toast('Enter your full name.', error: true);
                              return;
                            }
                            if (phone.length < 10) {
                              _toast('Enter a valid 10-digit mobile number.',
                                  error: true);
                              return;
                            }
                            if (pass.length < 8) {
                              _toast('Password must be at least 8 characters.',
                                  error: true);
                              return;
                            }

                            setSheetState(() => submitting = true);
                            final error = await ref
                                .read(authProvider.notifier)
                                .register(
                                  fullName: name,
                                  password: pass,
                                  role: 'Parent',
                                  email: emailCtrl.text.trim(),
                                  phoneNumber: phone,
                                );
                            if (!sheetCtx.mounted) return;
                            setSheetState(() => submitting = false);

                            if (error == null) {
                              Navigator.pop(sheetCtx);
                              if (!mounted) return;
                              _toast('Welcome to SchoolConnect!');
                              _goToDashboard();
                            } else {
                              _toast(error, error: true);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Text(
                            'Create account',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'An administrator will link your children to your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
