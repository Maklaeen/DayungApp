import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/screens/dayungquestion.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String? selectedRole;

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

  // ignore: unused_element
  void _showTopSuccessDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Success',
      barrierColor: Colors.black38, // Slightly darker overlay for emphasis
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, anim1, anim2) {
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
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade600.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 400),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Registered Successfully!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const Login()),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.white24,
                      ),
                      child: const Text('Go to Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.5),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
    );
  }

  void _showTopErrorDialog(BuildContext context, String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Error',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, anim1, anim2) {
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
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade600.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 400),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.white, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      tooltip: 'Dismiss',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.5),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final role = 'member';

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'role': role},
      );
      final user = res.user;

      if (user == null) {
        _showTopErrorDialog(context, 'Failed to register user.');
        return;
      }

      final int monthIndex = _months.indexOf(selectedMonth!) + 1;
      final dob = DateTime(
        int.parse(selectedYear!),
        monthIndex,
        int.parse(selectedDay!),
      ).toIso8601String().split('T').first; // → "YYYY-MM-DD"

      final insertRes = await Supabase.instance.client
          .from('users')
          .insert({
            'id': user.id,
            'full_name': fullNameController.text.trim(),
            'dob': dob,
            'sex': selectedSex,
            'mobile_number': mobileController.text.trim(),
            'address': addressController.text.trim(),
            'birth_certificate_url': '',
            'marriage_certificate_url': '',
            'role': role,
          })
          .select()
          .single();

      if (insertRes.error != null) {
        _showTopErrorDialog(context, insertRes.error!.message);
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QuestionnaireScreen(userId: user.id, role: role),
        ),
      );
    } catch (e) {
      // Handle any errors that occur during the sign-up or insertion process
      _showTopErrorDialog(context, 'Error: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 48),
                Image.asset(
                  'assets/images/dayunglogo.jpeg',
                  width: isWide ? 260 : 180,
                  height: isWide ? 90 : 60,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                AutoSizeText(
                  'Tabang sa Kalisud, Sa Isa ka Tap.',
                  style: TextStyle(
                    fontSize: isWide ? 20 : 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    fontFamily: 'OpenSans',
                  ),
                  maxLines: 1,
                  minFontSize: 12,
                ),
                const SizedBox(height: 36),

                _overlapLabelField(
                  'Full Name',
                  _customTextField(
                    hint: 'Juan Dela Cruz',
                    controller: fullNameController,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Full Name is required';
                      }
                      return null;
                    },
                    isWide: isWide,
                  ),
                  isWide: isWide,
                ),

                _overlapLabelField(
                  'Email',
                  _customTextField(
                    hint: 'example@email.com',
                    controller: emailController,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(val)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                    isWide: isWide,
                  ),
                  isWide: isWide,
                ),

                _overlapLabelField(
                  'Date of Birth',
                  Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: _customDropdown(
                          hint: 'Month',
                          items: _months,
                          value: selectedMonth,
                          onChanged: (val) =>
                              setState(() => selectedMonth = val),
                          validator: (val) =>
                              val == null ? 'Month is required' : null,
                          isWide: isWide,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: _customDropdown(
                          hint: 'Day',
                          items: List.generate(31, (i) => '${i + 1}'),
                          value: selectedDay,
                          onChanged: (val) => setState(() => selectedDay = val),
                          validator: (val) =>
                              val == null ? 'Day is required' : null,
                          isWide: isWide,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 3,
                        child: _customDropdown(
                          hint: 'Year',
                          items: List.generate(
                            100,
                            (i) => '${DateTime.now().year - i}',
                          ),
                          value: selectedYear,
                          onChanged: (val) =>
                              setState(() => selectedYear = val),
                          validator: (val) =>
                              val == null ? 'Year is required' : null,
                          isWide: isWide,
                        ),
                      ),
                    ],
                  ),
                  isWide: isWide,
                ),

                _overlapLabelField(
                  'Sex',
                  _customDropdown(
                    hint: 'Select Sex',
                    items: ['Male', 'Female'],
                    onChanged: (val) => setState(() => selectedSex = val),
                    validator: (val) => val == null ? 'Sex is required' : null,
                    isWide: isWide,
                  ),
                  isWide: isWide,
                ),

                _overlapLabelField(
                  'Mobile Number',
                  _customTextField(
                    hint: '+63 9XXXXXXXXX',
                    controller: mobileController,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Mobile number is required';
                      }
                      return null;
                    },
                    isWide: isWide,
                  ),
                  isWide: isWide,
                ),

                _overlapLabelField(
                  'Address',
                  _customTextField(
                    hint: 'Purok, Barangay, City',
                    controller: addressController,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Address is required';
                      }
                      return null;
                    },
                    isWide: isWide,
                  ),
                  isWide: isWide,
                ),

                _overlapLabelField(
                  'Create Password',
                  TextFormField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Password is required';
                      }
                      if (val.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: '********',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                  isWide: MediaQuery.of(context).size.width > 700,
                ),

                _overlapLabelField(
                  'Confirm Password',
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Confirm your password';
                      }
                      if (val != passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: '********',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      errorText: _confirmPasswordError,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                  isWide: MediaQuery.of(context).size.width > 700,
                ),

                // ...file pickers and other fields...
                const SizedBox(height: 36),

                SizedBox(
                  width: double.infinity,
                  height: isWide ? 56 : 48,
                  child: ElevatedButton(
                    onPressed: _registerUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565B3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: AutoSizeText(
                      'Submit',
                      style: TextStyle(
                        fontSize: isWide ? 22 : 18,
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Montserrat',
                      ),
                      maxLines: 1,
                      minFontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: isWide ? 56 : 48,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: const BorderSide(color: Color(0xFF1565B3)),
                    ),
                    child: AutoSizeText(
                      'Already have an account? Login',
                      style: TextStyle(
                        fontSize: isWide ? 18 : 14,
                        color: Color(0xFF1565B3),
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                      ),
                      maxLines: 1,
                      minFontSize: 10,
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlapLabelField(String label, Widget child, {bool isWide = false}) {
    return Container(
      margin: const EdgeInsets.only(top: 25, bottom: 8),
      height: isWide ? 80 : 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3F86BF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: AutoSizeText(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: isWide ? 18 : 15,
                  fontFamily: 'Montserrat',
                ),
                maxLines: 1,
                minFontSize: 10,
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: isWide ? 36 : 32, child: child),
        ],
      ),
    );
  }

  Widget _customTextField({
    String? hint,
    bool obscure = false,
    TextEditingController? controller,
    String? Function(String?)? validator,
    bool isWide = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: isWide ? 18 : 16,
          horizontal: isWide ? 18 : 16,
        ),
      ),
      style: TextStyle(fontSize: isWide ? 18 : 16, fontFamily: 'OpenSans'),
    );
  }

  Widget _customDropdown({
    required String hint,
    required List<String> items,
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
    String? value,
    bool isWide = false,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: isWide ? 15 : 13,
          horizontal: isWide ? 15 : 13,
        ),
      ),
      value: value,
      validator: validator,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

Widget _filePickerField() {
  return Row(
    children: [
      Expanded(
        child: TextFormField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'Choose file',
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
          ),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        onPressed: () {},
        icon: const Icon(Icons.upload_outlined, color: Colors.black54),
      ),
    ],
  );
}

extension on PostgrestMap {
  get error => null;
}
