import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:capstone_app/Providers/role_router.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/screens/selectdayung.dart'
    hide kAccent, kPrimary, kBg;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:auto_size_text/auto_size_text.dart';

// color palette
const Color kPrimaryLight = Color(0xFF3B82F6);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kNeutralText = Color(0xFF111827);
const Color kSubtleText = Color(0xFF6B7280);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kBorderColor = Color(0xFFE5E7EB);
const Color kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _forgotPassword() async {
    final input = emailController.text.trim(); // phone or email
    if (input.isEmpty) {
      _showErrorDialog('Missing Phone', 'Please enter your phone number.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? email;
      if (input.contains('@')) {
        email = input;
      } else {
        email = await _emailForPhone(input);
      }

      if (email == null || email.isEmpty) {
        setState(() => _isLoading = false);
        await _showErrorDialog(
          'Not found',
          'We could not find an account for that phone.',
        );
        return;
      }

      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      setState(() => _isLoading = false);
      await _showErrorDialog(
        'Check Your Email',
        'We sent a password reset link to $email.',
        color: kAccent,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      await _showErrorDialog(
        'Reset Failed',
        'Could not send reset link. Please try again.',
      );
    }
  }

  Future<void> _showErrorDialog(
    String title,
    String message, {
    Color color = kDanger,
    VoidCallback? onTryAgain,
  }) async {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Error',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        const BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    message,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: const BorderSide(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text(
                                    'Close',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    if (onTryAgain != null) onTryAgain();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: color,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Try again',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
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
        );
      },
    );
  }

  bool _looksOffline(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('failed to fetch') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('socketexception') ||
        s.contains('handshake');
  }

  String _normalizePhone(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), '');
    if (s.startsWith('+')) return s;
    // Simple PH normalization: 09XXXXXXXXX -> +639XXXXXXXXX
    if (s.startsWith('09') && s.length == 11) {
      return '+63${s.substring(1)}';
    }
    return s; // fallback
  }

  Future<String?> _emailForPhone(String phone) async {
    final sb = Supabase.instance.client;
    final normalized = _normalizePhone(phone);
    final email = await sb.rpc(
      'auth_email_for_phone',
      params: {'p_mobile': normalized},
    );
    if (email == null) return null;
    final e = (email as String).trim();
    return e.isEmpty ? null : e;
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final inputRaw = emailController.text.trim();
    final password = passwordController.text.trim();

    try {
      final resolvedEmail = inputRaw.contains('@')
          ? inputRaw.trim()
          : await _emailForPhone(inputRaw);

      if (resolvedEmail == null) {
        setState(() => _isLoading = false);
        await _showErrorDialog('Sign-in Failed', 'No account for that phone.');
        return;
      }

      final res = await Supabase.instance.client.auth
          .signInWithPassword(
            email: resolvedEmail.toLowerCase(),
            password: password,
          )
          .timeout(const Duration(seconds: 20));

      setState(() => _isLoading = false);

      if (res.user == null) {
        await _showErrorDialog('Sign-in Failed', 'Invalid credentials.');
        return;
      }

      // Log to audit_logs table
      await Supabase.instance.client.from('audit_logs').insert({
        'action': 'Signed in successfully',
        'created_at': DateTime.now().toIso8601String(),
        'user_id': res.user!.id,
      });

      await _routeAfterLogin({'id': res.user!.id});
    } on AuthException catch (e) {
      setState(() => _isLoading = false);
      debugPrint('AUTH ERROR code=${e.statusCode} msg=${e.message}');

      // Diagnostic: does stored bcrypt match entered password?
      try {
        final row = await Supabase.instance.client
            .from('users')
            .select('password_hash')
            .eq(
              'email',
              inputRaw.contains('@')
                  ? inputRaw
                  : await _emailForPhone(inputRaw) ?? '',
            )
            .maybeSingle();
        if (row != null && row['password_hash'] is String) {
          final okBcrypt = BCrypt.checkpw(
            password,
            row['password_hash'] as String,
          );
          debugPrint('Local bcrypt match: $okBcrypt');
        }
      } catch (_) {}

      await _showErrorDialog('Sign-in Failed', e.message);
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Generic login error: $e');
      await _showErrorDialog(
        _looksOffline(e) ? 'No Internet Connection' : 'Sign-in Failed',
        _looksOffline(e)
            ? 'Connect to your internet connection'
            : 'Please check your credentials and try again.',
        color: _looksOffline(e) ? kWarn : kDanger,
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: kSubtleText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(color: kSubtleText, fontSize: 16),
      prefixIcon: icon != null
          ? Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: kPrimary, size: 20),
            )
          : null,
      filled: true,
      fillColor: kCardBg,
      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kBorderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
      errorStyle: const TextStyle(
        color: kDanger,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Future<void> _routeAfterLogin(PostgrestMap userRow) async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;

    // 1. Check if user is SuperAdmin
    final userRowRole = await sb
        .from('users')
        .select('role')
        .eq('id', uid as Object)
        .maybeSingle();
    if (userRowRole?['role'] == 'superadmin') {
      await context.read<DayungRoleProvider>().refreshRoles(null);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleRouter()),
      );
      return;
    }

    // 2. Proceed with your existing logic for officers/members
    final approvedApps = await sb
        .from('applications')
        .select('dayung_unit_id, approved_at')
        .eq('user_id', uid as Object)
        .eq('status', 'approved')
        .order('approved_at', ascending: false);
    final appList = List<Map<String, dynamic>>.from(approvedApps);
    final approvedIds = appList.map((a) => a['dayung_unit_id'] as int).toSet();

    final officerUnits = await sb
        .from('dayung_units')
        .select('id')
        .or('secretary_id.eq.$uid,treasurer_id.eq.$uid,president_id.eq.$uid');
    final officerIds = List<Map<String, dynamic>>.from(
      officerUnits,
    ).map((o) => o['id'] as int).toSet();

    Set<int> collectorIds = {};
    try {
      final cu = await sb
          .from('dayung_collectors')
          .select('dayung_unit_id')
          .eq('user_id', uid as Object);
      collectorIds = List<Map<String, dynamic>>.from(
        cu,
      ).map((e) => e['dayung_unit_id'] as int).toSet();
    } catch (_) {}

    final allIds = <int>{
      ...approvedIds,
      ...officerIds,
      ...collectorIds,
    }.toList();

    final prefs = await SharedPreferences.getInstance();

    // Try previously saved selection
    Map<String, dynamic>? saved;
    final rawSaved = prefs.getString('selectedDayungUnit');
    int? savedId;
    if (rawSaved != null) {
      try {
        saved = Map<String, dynamic>.from(jsonDecode(rawSaved));
        savedId = saved['id'] is int
            ? saved['id'] as int
            : int.tryParse('${saved['id']}');
      } catch (_) {}
    }

    Map<String, dynamic>? selected;

    final hasValidSaved = savedId != null && allIds.contains(savedId);

    if (allIds.length > 1 && !hasValidSaved) {
      // Need user to pick one
      final picked = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(builder: (_) => const SelectDayungPage()),
      );
      if (!mounted) return;
      selected = picked;
    } else if (hasValidSaved) {
      // Reuse previous
      selected = saved;
    } else if (allIds.length == 1) {
      // Only one: load it
      final onlyId = allIds.first;
      final u = await sb
          .from('dayung_units')
          .select('id, name, barangay, city, province')
          .eq('id', onlyId)
          .maybeSingle();
      if (u != null) selected = Map<String, dynamic>.from(u);
    }

    selected ??= {
      'id': null,
      'name': 'Dayung',
      'barangay': null,
      'city': null,
      'province': null,
    };

    await prefs.setString('selectedDayungUnit', jsonEncode(selected));
    await prefs.setString('selectedDayungUnitData', jsonEncode(selected));

    if (selected['id'] == null && allIds.isEmpty) {
      // attempt officer fallback
      final fallbackOfficerUnit = await context
          .read<DayungRoleProvider>()
          .ensureOfficerUnitSelection();
      if (fallbackOfficerUnit != null) {
        selected['id'] = fallbackOfficerUnit;
      }
    }

    final unitId = selected['id'] is int
        ? selected['id'] as int
        : int.tryParse('${selected['id']}');
    if (unitId != null && mounted) {
      context.read<DayungUnitProvider>().setDayungUnit(
        '${selected['name'] ?? 'Dayung'}',
        obj: selected,
      );
      await context.read<DayungRoleProvider>().refreshRoles(unitId);
    } else {
      // Last resort: officer fallback
      final officerUnit = await context
          .read<DayungRoleProvider>()
          .ensureOfficerUnitSelection();
      if (mounted && officerUnit != null) {
        context.read<DayungUnitProvider>().setDayungUnit(
          'Dayung',
          obj: {'id': officerUnit},
        );
        await context.read<DayungRoleProvider>().refreshRoles(officerUnit);
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleRouter()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 720;

    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                // AutoSizeText(
                                //   'Welcome',
                                //   style: TextStyle(
                                //     fontSize: isWide ? 40 : 34,
                                //     fontWeight: FontWeight.w800,
                                //     letterSpacing: 1.5,
                                //     color: kNeutralText,
                                //     fontFamily: 'Montserrat',
                                //   ),
                                //   maxLines: 1,
                                //   minFontSize: 22,
                                // ),
                                const SizedBox(height: 12),
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Da',
                                        style: TextStyle(
                                          fontSize: isWide ? 48 : 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                          color: kNeutralText,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'y',
                                        style: TextStyle(
                                          fontSize: isWide ? 48 : 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                          color: kNeutralText,
                                          fontFamily: 'Montserrat',
                                          // Add any special styling for the 'y' here
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'ung',
                                        style: TextStyle(
                                          fontSize: isWide ? 48 : 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                          color: kNeutralText,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AutoSizeText(
                                  'Tabang sa Kalisud, Sa Isa ka Tap.',
                                  style: TextStyle(
                                    fontSize: isWide ? 22 : 18,
                                    fontWeight: FontWeight.w600,
                                    color: kSubtleText,
                                    fontFamily: 'OpenSans',
                                  ),
                                  maxLines: 1,
                                  minFontSize: 14,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Card
                    Card(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      color: kCardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              if (_isLoading)
                                Container(
                                  // margin: const EdgeInsets.only(bottom: 16),
                                  // padding: const EdgeInsets.all(16),
                                  //decoration: BoxDecoration(
                                  //color: kPrimary.withOpacity(0.1),
                                  //borderRadius: BorderRadius.circular(12),
                                  //),
                                  // child: Row(
                                  //   children: [
                                  //     const SizedBox(
                                  //       width: 20,
                                  //       height: 20,
                                  //       // child: CircularProgressIndicator(
                                  //       //   color: kPrimary,
                                  //       //   strokeWidth: 2,
                                  //       // ),
                                  //     ),
                                  //     const SizedBox(width: 12),
                                  //     // Text(
                                  //     //   'Signing you in...',
                                  //     //   style: TextStyle(
                                  //     //     color: kPrimary,
                                  //     //     fontWeight: FontWeight.w600,
                                  //     //     fontSize: 14,
                                  //     //   ),
                                  //     // ),
                                  //   ],
                                  // ),
                                ),

                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                style: TextStyle(
                                  fontSize: isWide ? 20 : 18,
                                  color: kNeutralText,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: _inputDecoration(
                                  'Phone number (or email)',
                                  icon: Icons.phone_rounded,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Phone number is required';
                                  }
                                  final s = value.trim();
                                  if (s.contains('@')) {
                                    final emailRegex = RegExp(
                                      r'^[^@]+@[^@]+\.[^@]+$',
                                    );
                                    if (!emailRegex.hasMatch(s)) {
                                      return 'Enter a valid email';
                                    }
                                    return null;
                                  }
                                  // Basic phone validation: 10–15 digits, allow leading +
                                  final phone = s.replaceAll(
                                    RegExp(r'\s+'),
                                    '',
                                  );
                                  if (!RegExp(
                                    r'^\+?\d{10,15}$',
                                  ).hasMatch(phone)) {
                                    return 'Enter a valid phone number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // Password
                              TextFormField(
                                controller: passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _handleLogin(),
                                style: TextStyle(
                                  fontSize: isWide ? 20 : 18,
                                  color: kNeutralText,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration:
                                    _inputDecoration(
                                      'Password',
                                      icon: Icons.lock_rounded,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'Show password'
                                            : 'Hide password',
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          color: kSubtleText,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                    ),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? 'Password is required'
                                    : null,
                              ),
                              const SizedBox(height: 24),

                              // Sign in button
                              Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [kPrimary, kPrimaryLight],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(kEdge),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimary.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        kEdge,
                                      ),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 26,
                                          width: 26,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 3,
                                          ),
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Secondary actions
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _forgotPassword,
                                      child: const Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          color: kPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => Navigator.pushNamed(
                                              context,
                                              '/register',
                                            ),
                                      child: const Text(
                                        'Create account',
                                        style: TextStyle(
                                          color: kPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
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

                    const SizedBox(height: 20),

                    // Helpful tip (for seniors)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: kSuccess.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kSuccess.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            color: kSuccess,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Need help? Ask a family member to assist you signing in.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: kSuccess,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
