import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/school_providers.dart';

enum AuthMethod { whatsappOtp, password, emailOtp }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // Method toggle - WhatsApp OTP vs Password vs Email OTP
  AuthMethod _authMethod = AuthMethod.whatsappOtp;

  // WhatsApp OTP fields
  final _phoneController = TextEditingController();
  final _whatsappOtpController = TextEditingController();
  bool _whatsappOtpSent = false;

  // Password fields
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Email OTP fields
  final _emailController = TextEditingController();
  final _emailOtpController = TextEditingController();
  bool _emailOtpSent = false;

  // Timer fields
  Timer? _countdownTimer;
  int _remainingSeconds = 300; // 5 minutes validity
  int _cooldownSeconds = 60; // 60 seconds resend cooldown
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
    _emailController.dispose();
    _emailOtpController.dispose();
    super.dispose();
  }

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
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        }
        if (_cooldownSeconds > 0) {
          _cooldownSeconds--;
        } else {
          _canResend = true;
        }
        if (_remainingSeconds <= 0 && _cooldownSeconds <= 0) {
          timer.cancel();
        }
      });
    });
  }

  void _resetOtpFlow() {
    _countdownTimer?.cancel();
    setState(() {
      _whatsappOtpSent = false;
      _emailOtpSent = false;
      _whatsappOtpController.clear();
      _emailOtpController.clear();
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

  // ═══════════════════════════════════════════════════════
  // WHATSAPP OTP ACTIONS
  // ═══════════════════════════════════════════════════════
  void _handleSendWhatsAppOtp() async {
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number.'),
          backgroundColor: AppColors.priorityUrgentText,
        ),
      );
      return;
    }

    final result = await ref.read(authProvider.notifier).sendWhatsAppOtp(phone);
    if (!mounted) return;

    if (result['success'] == true || result['message'] != null || result['status'] == 'success') {
      setState(() {
        _whatsappOtpSent = true;
      });
      _startTimers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'OTP sent to your WhatsApp successfully! 💬'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } else {
      final rawError = result['detail']?.toString() ??
          result['error']?.toString() ??
          ref.read(authProvider).errorMessage ??
          'Failed to send WhatsApp OTP. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rawError), backgroundColor: AppColors.priorityUrgentText),
      );
    }
  }

  void _handleVerifyWhatsAppOtp() async {
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final otp = _whatsappOtpController.text.trim();

    if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit OTP received on WhatsApp.'),
          backgroundColor: AppColors.priorityUrgentText,
        ),
      );
      return;
    }

    final success = await ref.read(authProvider.notifier).verifyWhatsAppOtp(phone, otp);
    if (!mounted) return;

    if (success) {
      _countdownTimer?.cancel();
      ref.read(classesProvider.notifier).refresh();
      ref.read(studentsProvider.notifier).refresh();
      ref.read(homeworkProvider.notifier).refresh();
      ref.read(announcementsProvider.notifier).refresh();
      context.go('/dashboard');
    } else {
      final rawError = ref.read(authProvider).errorMessage ?? 'Incorrect OTP. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rawError), backgroundColor: AppColors.priorityUrgentText),
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // PASSWORD ACTIONS
  // ═══════════════════════════════════════════════════════
  void _handlePasswordLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your username and password')),
      );
      return;
    }

    final success = await ref.read(authProvider.notifier).login(username, password);
    if (!mounted) return;

    if (success) {
      ref.read(classesProvider.notifier).refresh();
      ref.read(studentsProvider.notifier).refresh();
      ref.read(homeworkProvider.notifier).refresh();
      ref.read(announcementsProvider.notifier).refresh();
      context.go('/dashboard');
    } else {
      final error = ref.read(authProvider).errorMessage ?? 'Login failed. Please check credentials.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.priorityUrgentText),
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // EMAIL OTP ACTIONS
  // ═══════════════════════════════════════════════════════
  void _handleSendEmailOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
          backgroundColor: AppColors.priorityUrgentText,
        ),
      );
      return;
    }

    final result = await ref.read(authProvider.notifier).sendEmailOtp(email);
    if (!mounted) return;

    if (result['detail'] != null || result['success'] == true) {
      setState(() {
        _emailOtpSent = true;
      });
      _startTimers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['detail']?.toString() ?? 'OTP sent to your email address.'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } else {
      final rawError = result['error']?.toString() ??
          ref.read(authProvider).errorMessage ??
          'Failed to send OTP. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rawError), backgroundColor: AppColors.priorityUrgentText),
      );
    }
  }

  void _handleVerifyEmailOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    final otp = _emailOtpController.text.trim();

    if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit OTP received in your email.'),
          backgroundColor: AppColors.priorityUrgentText,
        ),
      );
      return;
    }

    final success = await ref.read(authProvider.notifier).verifyEmailOtp(email, otp);
    if (!mounted) return;

    if (success) {
      _countdownTimer?.cancel();
      ref.read(classesProvider.notifier).refresh();
      ref.read(studentsProvider.notifier).refresh();
      ref.read(homeworkProvider.notifier).refresh();
      ref.read(announcementsProvider.notifier).refresh();
      context.go('/dashboard');
    } else {
      final rawError = ref.read(authProvider).errorMessage ?? 'Incorrect OTP. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rawError), backgroundColor: AppColors.priorityUrgentText),
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // REGISTRATION DIALOG
  // ═══════════════════════════════════════════════════════
  void _showRegistrationDialog(BuildContext context) {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: _phoneController.text);
    final emailCtrl = TextEditingController();
    String selectedRole = 'Teacher';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Create School Account',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Register as a Teacher or Parent under Bizentrix SchoolConnect.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),

                // First & Last Name
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: firstCtrl,
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          hintText: 'First name',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: lastCtrl,
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          hintText: 'Last name',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Phone
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'WhatsApp Mobile Number',
                    prefixText: '+91 ',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // Email
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address (Optional)',
                    hintText: 'name@school.edu',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // Role Selector
                const Text(
                  'Select Your Role:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: ['Teacher', 'Parent', 'Admin'].map((role) {
                    final isSel = selectedRole == role;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => selectedRole = role),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.primary : AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSel ? AppColors.primary : AppColors.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            role,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSel ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Submit Button
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final first = firstCtrl.text.trim();
                      final phone = phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                      if (first.isEmpty || phone.length < 10) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter your first name and a valid 10-digit mobile number.'),
                            backgroundColor: AppColors.priorityUrgentText,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      setState(() {
                        _phoneController.text = phone;
                        _authMethod = AuthMethod.whatsappOtp;
                      });
                      _handleSendWhatsAppOtp();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Register & Send OTP', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // Brand Emblem / Official School Logo
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            AppConstants.schoolLogoPath,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.school_rounded,
                              size: 34,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // App Title & Tagline
                    const Text(
                      AppConstants.schoolName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '${AppConstants.schoolBranch} • ${AppConstants.schoolEstablished}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      AppConstants.schoolTagline,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Welcome Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Welcome Back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Sign in to your school account',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3-Way Auth Mode Toggle
                          _buildAuthModeSwitcher(),
                          const SizedBox(height: 18),

                          // Active Flow (WhatsApp OTP vs Password vs Email OTP)
                          if (_authMethod == AuthMethod.whatsappOtp)
                            _buildWhatsAppOtpForm(authState)
                          else if (_authMethod == AuthMethod.password)
                            _buildPasswordForm(authState)
                          else
                            _buildEmailOtpForm(authState),

                          const SizedBox(height: 16),

                          // Register Link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Don't have an account? ",
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              GestureDetector(
                                onTap: () => _showRegistrationDialog(context),
                                child: const Text(
                                  'Register Now',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Bottom School Building Graphic
            _buildSchoolIllustration(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 3-WAY SEGMENTED SWITCHER (WHATSAPP vs PASSWORD vs EMAIL)
  // ═══════════════════════════════════════════════════════
  Widget _buildAuthModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // WhatsApp OTP Tab
          _buildSegmentTab(
            method: AuthMethod.whatsappOtp,
            title: 'WhatsApp',
            icon: Icons.chat_bubble_rounded,
            activeColor: const Color(0xFF25D366),
          ),
          const SizedBox(width: 4),

          // Password Tab
          _buildSegmentTab(
            method: AuthMethod.password,
            title: 'Password',
            icon: Icons.lock_outline_rounded,
            activeColor: AppColors.primary,
          ),
          const SizedBox(width: 4),

          // Email OTP Tab
          _buildSegmentTab(
            method: AuthMethod.emailOtp,
            title: 'Email',
            icon: Icons.mark_email_read_outlined,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTab({
    required AuthMethod method,
    required String title,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _authMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_authMethod != method) {
            _resetOtpFlow();
            setState(() => _authMethod = method);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
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
                size: 15,
                color: isSelected ? activeColor : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // WHATSAPP OTP FORM
  // ═══════════════════════════════════════════════════════
  Widget _buildWhatsAppOtpForm(AuthState authState) {
    if (!_whatsappOtpSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'WhatsApp Mobile Number',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),

          // Phone input with +91 prefix
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(11)),
                  ),
                  child: const Row(
                    children: [
                      Text('🇮🇳', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 4),
                      Text(
                        '+91',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                    decoration: const InputDecoration(
                      hintText: 'Enter 10-digit number',
                      hintStyle: TextStyle(color: AppColors.textMuted, letterSpacing: 0),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Send WhatsApp OTP Button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: authState.isLoading ? null : _handleSendWhatsAppOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: authState.isLoading
                  ? const SizedBox.shrink()
                  : const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: authState.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Send OTP via WhatsApp',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 10),

          const Center(
            child: Text(
              'A 6-digit verification code will be sent via Meta WhatsApp Cloud API.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      );
    } else {
      // Step 2: Verify WhatsApp OTP
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.mark_chat_read_rounded, size: 18, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'OTP sent to +91 ${_phoneController.text}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B5E20),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: _resetOtpFlow,
                  child: const Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          const Text(
            'Enter 6-Digit WhatsApp Code',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),

          // 6-digit OTP Input
          TextField(
            controller: _whatsappOtpController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '••••••',
              hintStyle: const TextStyle(letterSpacing: 10, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF25D366), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Timers & Resend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Expires in: ${_formatTimer(_remainingSeconds)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _remainingSeconds <= 60 ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (_canResend)
                GestureDetector(
                  onTap: authState.isLoading ? null : _handleSendWhatsAppOtp,
                  child: const Text(
                    'Resend OTP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF25D366),
                    ),
                  ),
                )
              else
                Text(
                  'Resend in ${_cooldownSeconds}s',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Verify Button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: authState.isLoading ? null : _handleVerifyWhatsAppOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: authState.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Verify & Login',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // PASSWORD LOGIN FORM
  // ═══════════════════════════════════════════════════════
  Widget _buildPasswordForm(AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Username',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.person_outline, size: 20, color: AppColors.textMuted),
            hintText: 'Enter username',
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 14),

        const Text(
          'Password',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline, size: 20, color: AppColors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AppColors.textMuted),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            hintText: 'Enter password',
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 18),

        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: authState.isLoading ? null : _handlePasswordLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: authState.isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Login', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),

        Center(
          child: TextButton(
            onPressed: () {},
            child: const Text('Forgot Password?', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // EMAIL OTP FORM
  // ═══════════════════════════════════════════════════════
  Widget _buildEmailOtpForm(AuthState authState) {
    if (!_emailOtpSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Email Address',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppColors.textMuted),
              hintText: 'Enter your registered email',
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: authState.isLoading ? null : _handleSendEmailOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: authState.isLoading ? const SizedBox.shrink() : const Icon(Icons.send_rounded, size: 18),
              label: authState.isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send Email OTP', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.mark_email_read_rounded, size: 18, color: Color(0xFF1D4ED8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'OTP sent to ${_emailController.text}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: _resetOtpFlow,
                  child: const Text(
                    'Change',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          const Text('Enter 6-Digit Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),

          TextField(
            controller: _emailOtpController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '••••••',
              hintStyle: const TextStyle(letterSpacing: 10, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Expires in: ${_formatTimer(_remainingSeconds)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _remainingSeconds <= 60 ? Colors.red : AppColors.textSecondary),
                  ),
                ],
              ),
              if (_canResend)
                GestureDetector(
                  onTap: authState.isLoading ? null : _handleSendEmailOtp,
                  child: const Text('Resend OTP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                )
              else
                Text('Resend in ${_cooldownSeconds}s', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: authState.isLoading ? null : _handleVerifyEmailOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: authState.isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify & Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildSchoolIllustration() {
    return Container(
      width: double.infinity,
      height: 110,
      margin: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/school_campus.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF1E293B),
              child: const Center(
                child: Icon(Icons.school, size: 36, color: Colors.white54),
              ),
            ),
          ),
          // Subtle gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
          // Clean campus badge
          Positioned(
            bottom: 8,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified, color: Color(0xFF38BDF8), size: 12),
                      SizedBox(width: 4),
                      Text(
                        '${AppConstants.schoolName} • ${AppConstants.schoolBranch}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Academic Session ${AppConstants.currentAcademicYear}',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
