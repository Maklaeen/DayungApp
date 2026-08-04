import 'package:capstone_app/Auth/pin_pad_widget.dart';
import 'package:capstone_app/Auth/pin_service.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key});

  @override
  State<PinLockPage> createState() => _PinLockPageState();
}

class _PinLockPageState extends State<PinLockPage> {
  final List<String> _digits = [];
  int _attempts = 0;
  String? _error;
  bool _loading = false;

  void _onDigit(String d) {
    if (_digits.length >= 4 || _loading) return;
    setState(() {
      _digits.add(d);
      _error = null;
    });
    if (_digits.length == 4) _verify();
  }

  void _onDelete() {
    if (_digits.isEmpty || _loading) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final ok = await PinService.verifyPin(uid, _digits.join());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      _attempts++;
      setState(() {
        _digits.clear();
        _loading = false;
        _error = _attempts >= 3
            ? 'Too many attempts. Use your password instead.'
            : 'Incorrect PIN (${3 - _attempts} attempt${3 - _attempts == 1 ? '' : 's'} left)';
      });
    }
  }

  Future<void> _forgotPin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Forgot PIN?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        content: const Text(
          'Your PIN will be cleared and you\'ll be signed out to log in with your password.',
          style: TextStyle(fontFamily: 'OpenSans', height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            child: const Text('Clear PIN & Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PinService.clearPin();
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: Column(
            children: [
              // Top branding strip
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: isWide ? 24 : 18,
                  horizontal: isWide ? 32 : 20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Dayung',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              // PIN pad
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kPrimary),
                      )
                    : PinPad(
                        title: 'Welcome back!',
                        subtitle: 'Enter your PIN to continue',
                        filledCount: _digits.length,
                        error: _error,
                        onDigit: _onDigit,
                        onDelete: _onDelete,
                        bottomAction: TextButton.icon(
                          onPressed: _forgotPin,
                          icon: const Icon(
                            Icons.help_outline_rounded,
                            size: 16,
                            color: kSubtleText,
                          ),
                          label: const Text(
                            'Forgot PIN?',
                            style: TextStyle(
                              color: kSubtleText,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'OpenSans',
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
