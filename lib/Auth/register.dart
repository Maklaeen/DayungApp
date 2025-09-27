import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/screens/dayungquestion.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kEdge = 18;

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

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _confirmPasswordError;
  bool _isSubmitting = false;

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
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: kDanger.withOpacity(0.98),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close, color: Colors.white),
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

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_confirmPasswordError != null) return;

    setState(() => _isSubmitting = true);

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    const role = 'member';

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

      final int monthIndex = _months.indexOf(selectedMonth!) + 1;
      final dob = DateTime(
        int.parse(selectedYear!),
        monthIndex,
        int.parse(selectedDay!),
      ).toIso8601String().split('T').first; // YYYY-MM-DD

      // Insert profile row; errors will throw and be caught by catch
      await Supabase.instance.client.from('users').insert({
        'id': user.id,
        'full_name': fullNameController.text.trim(),
        'dob': dob,
        'sex': selectedSex,
        'mobile_number': mobileController.text.trim(),
        'address': addressController.text.trim(),
        'birth_certificate_url': '',
        'marriage_certificate_url': '',
        'role': role,
      });

      setState(() => _isSubmitting = false);

      // Go to questions
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QuestionnaireScreen(userId: user.id, role: role),
        ),
      );
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showTopErrorDialog(context, 'Error: ${e.toString()}');
    }
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: kSubtleText, fontSize: 16),
      prefixIcon: icon != null ? Icon(icon, color: kSubtleText) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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
    );
  }

  InputDecoration _dropdownDec(String label) => _dec(label).copyWith(
    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 720;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/images/dayunglogo.jpeg',
                          width: isWide ? 280 : 220,
                          height: isWide ? 100 : 80,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 8),
                        AutoSizeText(
                          'Tabang sa Kalisud, Sa Isa ka Tap.',
                          maxLines: 1,
                          minFontSize: 12,
                          style: TextStyle(
                            fontSize: isWide ? 20 : 16,
                            fontWeight: FontWeight.w600,
                            color: kSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Form Card
                  Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    color: const Color.fromARGB(255, 232, 232, 232),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kEdge),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_isSubmitting)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator(
                                  color: kPrimary,
                                  backgroundColor: Color(0xFFEFF2F7),
                                  minHeight: 3,
                                ),
                              ),

                            // Section: Personal Info
                            Row(
                              children: const [
                                Icon(Icons.person_outline, color: kPrimary),
                                SizedBox(width: 8),
                                Text(
                                  'Personal Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kNeutralText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Full Name
                            TextFormField(
                              controller: fullNameController,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
                              ),
                              decoration: _dec(
                                'Full Name',
                                hint: 'Juan Dela Cruz',
                                icon: Icons.badge_outlined,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Full Name is required'
                                  : null,
                            ),
                            const SizedBox(height: 14),

                            // Sex
                            DropdownButtonFormField<String>(
                              value: selectedSex,
                              decoration: _dropdownDec('Sex'),
                              items: const ['Male', 'Female']
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => selectedSex = v),
                              validator: (v) =>
                                  v == null ? 'Sex is required' : null,
                            ),
                            const SizedBox(height: 14),

                            // Date of Birth
                            Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedMonth,
                                    decoration: _dropdownDec('Month'),
                                    items: _months
                                        .map(
                                          (m) => DropdownMenuItem(
                                            value: m,
                                            child: Text(m),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => selectedMonth = v),
                                    validator: (v) =>
                                        v == null ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedDay,
                                    decoration: _dropdownDec('Day'),
                                    items: List.generate(31, (i) => '${i + 1}')
                                        .map(
                                          (d) => DropdownMenuItem(
                                            value: d,
                                            child: Text(d),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => selectedDay = v),
                                    validator: (v) =>
                                        v == null ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedYear,
                                    decoration: _dropdownDec('Year'),
                                    items:
                                        List.generate(
                                              100,
                                              (i) =>
                                                  '${DateTime.now().year - i}',
                                            )
                                            .map(
                                              (y) => DropdownMenuItem(
                                                value: y,
                                                child: Text(y),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (v) =>
                                        setState(() => selectedYear = v),
                                    validator: (v) =>
                                        v == null ? 'Required' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Mobile
                            TextFormField(
                              controller: mobileController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
                              ),
                              decoration: _dec(
                                'Mobile Number',
                                hint: '+63 9XXXXXXXXX',
                                icon: Icons.phone_outlined,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Mobile number is required'
                                  : null,
                            ),
                            const SizedBox(height: 14),

                            // Address
                            TextFormField(
                              controller: addressController,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
                              ),
                              decoration: _dec(
                                'Address',
                                hint: 'Purok, Barangay, City',
                                icon: Icons.home_outlined,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Address is required'
                                  : null,
                            ),

                            const SizedBox(height: 24),

                            // Section: Account
                            Row(
                              children: const [
                                Icon(Icons.lock_outline, color: kPrimary),
                                SizedBox(width: 8),
                                Text(
                                  'Account',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kNeutralText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Email
                            TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
                              ),
                              decoration: _dec(
                                'Email',
                                hint: 'example@email.com',
                                icon: Icons.email_outlined,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty)
                                  return 'Email is required';
                                if (!RegExp(
                                  r'^[^@]+@[^@]+\.[^@]+',
                                ).hasMatch(v.trim()))
                                  return 'Enter a valid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Password
                            TextFormField(
                              controller: passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
                              ),
                              decoration:
                                  _dec(
                                    'Create Password',
                                    hint: '********',
                                    icon: Icons.password_outlined,
                                  ).copyWith(
                                    helperText: 'At least 6 characters',
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubtleText,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                  ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty)
                                  return 'Password is required';
                                if (v.trim().length < 6)
                                  return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Confirm Password
                            TextFormField(
                              controller: confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              textInputAction: TextInputAction.done,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
                              ),
                              decoration:
                                  _dec(
                                    'Confirm Password',
                                    hint: '********',
                                    icon: Icons.lock_person_outlined,
                                  ).copyWith(
                                    errorText: _confirmPasswordError,
                                    suffixIcon: IconButton(
                                      tooltip: _obscureConfirmPassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubtleText,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscureConfirmPassword =
                                            !_obscureConfirmPassword,
                                      ),
                                    ),
                                  ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty)
                                  return 'Confirm your password';
                                if (v != passwordController.text)
                                  return 'Passwords do not match';
                                return null;
                              },
                            ),

                            const SizedBox(height: 24),

                            // Submit
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isSubmitting ? null : _registerUser,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  disabledBackgroundColor: kPrimaryDark
                                      .withOpacity(0.5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(kEdge),
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
                                        'Submit',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Back to login
                            SizedBox(
                              width: double.infinity,
                              height: 56,
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
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(kEdge),
                                  ),
                                  side: const BorderSide(
                                    color: kPrimary,
                                    width: 1.5,
                                  ),
                                  foregroundColor: kPrimary,
                                ),
                                child: const Text(
                                  'Already have an account? Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Your information is kept private and secure.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kSubtleText, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
