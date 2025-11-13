import 'package:auto_size_text/auto_size_text.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:capstone_app/Auth/utils_file.dart';
import 'package:capstone_app/screens/dayungquestion.dart'
    hide kPrimary, kBg, kAccent;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// palette
const Color kPrimaryLight = Color(0xFF3B82F6);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kNeutralText = Color(0xFF111827);
const Color kSubtleText = Color(0xFF6B7280);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kBorderColor = Color(0xFFE5E7EB);
const Color kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final sexController = TextEditingController();
  final mobileController = TextEditingController();
  final addressController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String get password => passwordController.text.trim();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _confirmPasswordError;
  bool _isSubmitting = false;
  DateTime? _selectedDob;

  @override
  void initState() {
    super.initState();
    confirmPasswordController.addListener(_checkPasswordMatch);
    passwordController.addListener(_checkPasswordMatch);
  }

  void _checkPasswordMatch() {
    final password = passwordController.text;
    final confirm = confirmPasswordController.text;
    setState(() {
      if (confirm.isEmpty) {
        _confirmPasswordError = null;
      } else if (password != confirm) {
        _confirmPasswordError = 'Passwords do not match';
      } else {
        _confirmPasswordError = null;
      }
    });
  }

  String? selectedMonth;
  String? selectedDay;
  String? selectedYear;
  String? selectedSex;

  String _normalizePhone(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), '');
    if (s.startsWith('+')) return s;
    if (s.startsWith('09') && s.length == 11) {
      return '+63${s.substring(1)}';
    }
    return s;
  }

  // ignore: unused_field
  final List<String> _months = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    fullNameController.dispose();
    sexController.dispose();
    mobileController.dispose();
    addressController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    emailController.dispose();
    confirmPasswordController.removeListener(_checkPasswordMatch);
    passwordController.removeListener(_checkPasswordMatch);
    super.dispose();
  }

  void _showTopErrorDialog(BuildContext context, String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Error',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, a1, a2) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kDanger, kDanger.withOpacity(0.9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: kDanger.withOpacity(0.3),
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
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, a1, a2, child) => FadeTransition(
        opacity: a1,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(a1),
          child: child,
        ),
      ),
    );
  }

  Future<void> _showCalendarDialog(BuildContext context) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 100, 1, 1);
    final lastDate = now;
    final initialDate = _selectedDob ?? DateTime(now.year - 18, 1, 1);

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        DateTime temp = initialDate;
        final size = MediaQuery.of(ctx).size;

        return SafeArea(
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.light,
              primaryColor: Color(0xFF3B82F6),
            ),
            child: SizedBox(
              height: size.height * 0.50,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: kDanger,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Select Date of Birth',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kNeutralText,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, temp),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: kPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: CupertinoCalendar(
                        minimumDateTime: firstDate,
                        maximumDateTime: lastDate,
                        initialDateTime: temp,
                        currentDateTime: _selectedDob ?? DateTime.now(),
                        mode: CupertinoCalendarMode.date,
                        onDateTimeChanged: (d) => temp = d,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_confirmPasswordError != null) return;

    setState(() => _isSubmitting = true);

    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text.trim();
    const role = 'member';

    final rawPhone = mobileController.text.trim();
    final normalizedPhone = _normalizePhone(rawPhone);

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'role': role},
      );

      final user = res.user;
      if (user == null) {
        setState(() => _isSubmitting = false);
        _showTopErrorDialog(context, 'Failed to register user.');
        return;
      }

      final dob = _selectedDob!.toIso8601String().split('T').first;

      await Supabase.instance.client.from('users').insert({
        'id': user.id,
        'full_name': fullNameController.text.trim(),
        'dob': dob,
        'sex': selectedSex,
        'mobile_number': rawPhone,
        'mobile_number_normalized': normalizedPhone,
        'address': addressController.text.trim(),
        'role': role,
        'email': email,
      });

      final hashed = BCrypt.hashpw(password, BCrypt.gensalt());
      await Supabase.instance.client
          .from('users')
          .update({'password_hash': hashed})
          .eq('id', user.id);

      setState(() => _isSubmitting = false);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QuestionnaireScreen(userId: user.id, role: role),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _isSubmitting = false);
      _showTopErrorDialog(context, 'Auth error: ${e.message}');
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showTopErrorDialog(context, 'Error: $e');
    }
  }

  Widget _dobField(BuildContext rootContext) {
    final isWide = MediaQuery.of(context).size.width > 720;

    return GestureDetector(
      onTap: () => _showCalendarDialog(rootContext),
      child: AbsorbPointer(
        child: TextFormField(
          readOnly: true,
          style: TextStyle(
            fontSize: isWide ? 18 : 16,
            color: kNeutralText,
            fontWeight: FontWeight.w500,
          ),
          decoration: _dec(
            'Date of Birth',
            hint: 'YYYY-MM-DD',
            icon: Icons.calendar_today_rounded,
          ),
          controller: TextEditingController(
            text: _selectedDob == null
                ? ''
                : '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}',
          ),
          validator: (v) =>
              _selectedDob == null ? 'Date of birth is required' : null,
        ),
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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

  InputDecoration _dropdownDec(String label) => _dec(label).copyWith(
    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 720;
    final isSmall = width < 350;

    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      body: Builder(
        builder: (rootContext) {
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmall ? 16 : 24,
                  vertical: isSmall ? 12 : 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 640 : 420),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: EdgeInsets.only(bottom: isSmall ? 12 : 20),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimary.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/dayunglogo.jpeg',
                                width: isWide ? 280 : (isSmall ? 120 : 220),
                                height: isWide ? 100 : (isSmall ? 40 : 80),
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(height: isSmall ? 8 : 12),
                            AutoSizeText(
                              'Tabang sa Kalisud, Sa Isa ka Tap.',
                              maxLines: 1,
                              minFontSize: 10,
                              style: TextStyle(
                                fontSize: isWide ? 20 : (isSmall ? 12 : 16),
                                fontWeight: FontWeight.w600,
                                color: kSubtleText,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Card(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        color: kCardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: kBorderColor.withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isSmall ? 10 : 20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                if (_isSubmitting)
                                  Container(
                                    margin: EdgeInsets.only(
                                      bottom: isSmall ? 8 : 16,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: kPrimary,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Creating your account...',
                                          style: TextStyle(
                                            color: kPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: kPrimary.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: kPrimary,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Personal Information',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: kNeutralText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: fullNameController,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _dec(
                                    'Full Name',
                                    hint: 'Juan Dela Cruz',
                                    icon: Icons.person_rounded,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Full Name is required'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedSex,
                                  decoration: _dropdownDec('Sex'),
                                  items: const ['Male', 'Female']
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(
                                            s,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => selectedSex = v),
                                  validator: (v) =>
                                      v == null ? 'Sex is required' : null,
                                ),
                                const SizedBox(height: 16),
                                _dobField(rootContext),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: mobileController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _dec(
                                    'Mobile Number',
                                    hint: '+63 9XXXXXXXXX',
                                    icon: Icons.phone_rounded,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Mobile number is required'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: addressController,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _dec(
                                    'Address',
                                    hint: 'Purok, Barangay, City',
                                    icon: Icons.home_rounded,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Address is required'
                                      : null,
                                ),

                                const SizedBox(height: 28),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kAccent.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: kAccent.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: kAccent,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.lock_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Account Information',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: kNeutralText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _dec(
                                    'Email',
                                    hint: 'example@email.com',
                                    icon: Icons.email_rounded,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Email is required';
                                    }
                                    if (!RegExp(
                                      r'^[^@]+@[^@]+\.[^@]+',
                                    ).hasMatch(v.trim())) {
                                      return 'Enter a valid email';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Password
                                TextFormField(
                                  controller: passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration:
                                      _dec(
                                        'Create Password',
                                        hint: '********',
                                        icon: Icons.lock_rounded,
                                      ).copyWith(
                                        helperText: 'At least 6 characters',
                                        helperStyle: TextStyle(
                                          color: kSubtleText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
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
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                        ),
                                      ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Password is required';
                                    }
                                    if (v.trim().length < 6) {
                                      return 'Password must be at least 6 characters';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: confirmPasswordController,
                                  obscureText: _obscureConfirmPassword,
                                  textInputAction: TextInputAction.done,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration:
                                      _dec(
                                        'Confirm Password',
                                        hint: '********',
                                        icon: Icons.lock_person_rounded,
                                      ).copyWith(
                                        errorText: _confirmPasswordError,
                                        suffixIcon: IconButton(
                                          tooltip: _obscureConfirmPassword
                                              ? 'Show password'
                                              : 'Hide password',
                                          icon: Icon(
                                            _obscureConfirmPassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                            color: kSubtleText,
                                          ),
                                          onPressed: () => setState(
                                            () => _obscureConfirmPassword =
                                                !_obscureConfirmPassword,
                                          ),
                                        ),
                                      ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Confirm your password';
                                    }
                                    if (v != passwordController.text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 28),
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
                                    onPressed: _isSubmitting
                                        ? null
                                        : _registerUser,
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
                                    child: _isSubmitting
                                        ? const SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 3,
                                            ),
                                          )
                                        : const Text(
                                            'Create Account',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(kEdge),
                                    border: Border.all(
                                      color: kBorderColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: OutlinedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const Login(),
                                            ),
                                          ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          kEdge,
                                        ),
                                      ),
                                      side: BorderSide.none,
                                      foregroundColor: kPrimary,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.arrow_back_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Already have an account? Login',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
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
                              Icons.security_rounded,
                              color: kSuccess,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Your information is kept private and secure.',
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
          );
        },
      ),
    );
  }
}
