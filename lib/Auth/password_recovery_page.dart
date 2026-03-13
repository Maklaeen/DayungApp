import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _saving = false;
  bool _hideNew = true;
  bool _hideConfirm = true;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    String label,
    IconData icon,
    bool obscure,
    VoidCallback toggle,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: kSubtleText),
      prefixIcon: Icon(icon, color: kPrimary),
      suffixIcon: IconButton(
        onPressed: toggle,
        icon: Icon(
          obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: kSubtleText,
        ),
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: kPrimary.withValues(alpha: 0.14)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: kPrimary.withValues(alpha: 0.14)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kPrimary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kDanger, width: 1.8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kDanger, width: 1.8),
      ),
    );
  }

  Future<void> _returnToLogin() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your reset session is missing or has expired.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final nextMetadata = Map<String, dynamic>.from(
        currentUser.userMetadata ?? {},
      );
      nextMetadata['force_password_change'] = false;
      nextMetadata['password_changed_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();

      await client.auth.updateUser(
        UserAttributes(
          password: _newPasswordController.text.trim(),
          data: nextMetadata,
        ),
      );

      try {
        await logAuditEvent(
          'USER_ACTIVITY_PASSWORD_CHANGED',
          userId: client.auth.currentUser?.id,
          fields: {'source': 'password_recovery_page'},
        );
      } catch (_) {}

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Password Updated'),
            content: const Text(
              'Your password has been updated. Please sign in again using the new password.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
      await _returnToLogin();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to update password right now. Please try the email link again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRecoverySession =
        Supabase.instance.client.auth.currentSession != null &&
        Supabase.instance.client.auth.currentUser != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.1)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 24,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: hasRecoverySession
                    ? Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(
                                  colors: [kPrimary, kPrimaryDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_reset_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Set Your New Password',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: kPrimaryDark,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'You opened a valid password reset link. Choose a new password to secure your Dayung account.',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: kSubtleText,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _newPasswordController,
                              obscureText: _hideNew,
                              inputFormatters:
                                  AppInputSecurity.singleLineFormatters(
                                    maxLength: 72,
                                  ),
                              decoration: _fieldDecoration(
                                'New password',
                                Icons.lock_outline_rounded,
                                _hideNew,
                                () => setState(() => _hideNew = !_hideNew),
                              ),
                              validator: (value) {
                                final password = value?.trim() ?? '';
                                if (password.length < 8) {
                                  return 'Password must be at least 8 characters.';
                                }
                                if (password.length > 72) {
                                  return 'Password must be 72 characters or less.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _hideConfirm,
                              inputFormatters:
                                  AppInputSecurity.singleLineFormatters(
                                    maxLength: 72,
                                  ),
                              decoration: _fieldDecoration(
                                'Confirm new password',
                                Icons.verified_user_outlined,
                                _hideConfirm,
                                () => setState(
                                  () => _hideConfirm = !_hideConfirm,
                                ),
                              ),
                              validator: (value) {
                                if ((value ?? '').trim() !=
                                    _newPasswordController.text.trim()) {
                                  return 'Passwords do not match.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: kPrimary.withValues(alpha: 0.12),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: kPrimary,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'After saving, you will return to the sign-in page and use your new password there.',
                                      style: TextStyle(
                                        color: kSubtleText,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _saving ? null : _returnToLogin,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(54),
                                      side: BorderSide(
                                        color: kPrimary.withValues(alpha: 0.14),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: kPrimaryDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _saving ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(54),
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: _saving
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Save Password',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: kDanger.withValues(alpha: 0.12),
                            ),
                            child: const Icon(
                              Icons.link_off_rounded,
                              color: kDanger,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Reset Link Expired',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: kPrimaryDark,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'This password reset link is no longer valid. Request a new one from the login screen and open it again on this device.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: kSubtleText,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _returnToLogin,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                backgroundColor: kPrimary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'Back to Login',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
