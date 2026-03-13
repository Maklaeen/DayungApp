import 'package:capstone_app/utils/input_safety.dart';
import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kForcePrimary = Color(0xFF17326B);
const kForceAccent = Color(0xFF0F9D7A);
const kForceBg = Color(0xFFF4F7FB);
const kForceText = Color(0xFF14213D);
const kForceMuted = Color(0xFF667085);
const kForceDanger = Color(0xFFC73A2C);
const kForceBorder = Color(0xFFD9E2F2);

class ForcePasswordChangePage extends StatefulWidget {
  const ForcePasswordChangePage({super.key});

  @override
  State<ForcePasswordChangePage> createState() =>
      _ForcePasswordChangePageState();
}

class _ForcePasswordChangePageState extends State<ForcePasswordChangePage> {
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
      labelStyle: const TextStyle(color: kForceMuted),
      prefixIcon: Icon(icon, color: kForcePrimary),
      suffixIcon: IconButton(
        onPressed: toggle,
        icon: Icon(
          obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: kForceMuted,
        ),
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kForceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kForceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kForcePrimary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kForceDanger, width: 1.8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kForceDanger, width: 1.8),
      ),
    );
  }

  Future<void> _signOut() async {
    await logAuditEvent(
      'USER_ACTIVITY_SIGN_OUT',
      fields: {'source': 'force_password_change_required'},
    );
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;

    try {
      final nextMetadata = Map<String, dynamic>.from(
        currentUser?.userMetadata ?? {},
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

      final updatedUserId = client.auth.currentUser?.id;
      if (updatedUserId != null) {
        try {
          await logAuditEvent(
            'PASSWORD_CHANGED_ON_FIRST_SIGN_IN',
            userId: updatedUserId,
            fields: {'source': 'force_password_change_page'},
          );
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
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
            'Unable to update password right now. Please try again.',
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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kForceBg,
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
                    border: Border.all(color: kForceBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Form(
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
                              colors: [kForcePrimary, kForceAccent],
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
                          'Change Your Temporary Password',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: kForceText,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'For account security, you need to set a new personal password before you can continue using Dayung.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: kForceMuted,
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
                            () => setState(() => _hideConfirm = !_hideConfirm),
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
                            border: Border.all(color: kForceBorder),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: kForcePrimary,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'If you leave this screen, you will be signed out and asked to log in again with the temporary password.',
                                  style: TextStyle(
                                    color: kForceMuted,
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
                                onPressed: _saving ? null : _signOut,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  side: const BorderSide(color: kForceBorder),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: const Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    color: kForceText,
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
                                  backgroundColor: kForcePrimary,
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
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
