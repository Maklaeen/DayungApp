import 'package:capstone_app/Providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:auto_size_text/auto_size_text.dart';

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

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      setState(() => _isLoading = false);

      if (res.user != null) {
        final userId = res.user!.id;

        // 🔑 fetch role from 'users' table
        final userData = await Supabase.instance.client
            .from('users')
            .select('role')
            .eq('id', userId)
            .maybeSingle();

        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.loadUserData();

        if (userData != null) {
          final role = userData['role'];

          if (role == 'member') {
            Navigator.pushReplacementNamed(context, '/dashboard');
          } else if (role == 'president') {
            Navigator.pushReplacementNamed(context, '/president-dashboard');
          } else if (role == 'secretary') {
            Navigator.pushReplacementNamed(context, '/secretary-dashboard');
          } else if (role == 'admin') {
            Navigator.pushReplacementNamed(context, '/admin-dashboard');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unknown user role'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found in users table'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid email or password'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              AutoSizeText(
                'WELCOME',
                style: TextStyle(
                  fontSize: isWide ? 36 : 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Colors.black,
                  fontFamily: 'Montserrat',
                ),
                maxLines: 1,
                minFontSize: 18,
              ),
              const SizedBox(height: 10),
              Image.asset(
                'assets/images/dayunglogo.jpeg',
                width: isWide ? 320 : 280,
                height: isWide ? 120 : 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              AutoSizeText(
                'Tabang sa Kalisud, Sa Isa ka Tap.',
                style: TextStyle(
                  fontSize: isWide ? 22 : 16,
                  color: Colors.black,
                  fontFamily: 'OpenSans',
                ),
                maxLines: 1,
                minFontSize: 12,
              ),
              const SizedBox(height: 40),

              // Email
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontSize: isWide ? 18 : 16),
                decoration: InputDecoration(
                  labelText: 'Enter email',
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: isWide ? 22 : 18,
                    horizontal: isWide ? 24 : 20,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  if (!emailRegex.hasMatch(value.trim())) {
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
                style: TextStyle(fontSize: isWide ? 18 : 16),
                decoration: InputDecoration(
                  labelText: 'Enter password',
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: isWide ? 22 : 18,
                    horizontal: isWide ? 24 : 20,
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
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Password is required'
                    : null,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B8FD7),
                    padding: EdgeInsets.symmetric(vertical: isWide ? 22 : 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : AutoSizeText(
                          'Sign In',
                          style: TextStyle(
                            fontSize: isWide ? 22 : 18,
                            color: Colors.white,
                            letterSpacing: 1,
                            fontFamily: 'Montserrat',
                          ),
                          maxLines: 1,
                          minFontSize: 12,
                        ),
                ),
              ),
              const SizedBox(height: 40),

              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: AutoSizeText(
                  'Create an account',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: isWide ? 20 : 16,
                    letterSpacing: 1,
                    fontFamily: 'OpenSans',
                  ),
                  maxLines: 1,
                  minFontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
