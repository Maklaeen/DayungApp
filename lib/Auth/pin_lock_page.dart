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
            : 'Incorrect PIN. Try again.';
      });
    }
  }

  Future<void> _forgotPin() async {
    await PinService.clearPin();
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: PinPad(
            title: 'Enter your PIN',
            subtitle: 'Use your 4-digit PIN to continue',
            filledCount: _digits.length,
            error: _error,
            onDigit: _onDigit,
            onDelete: _onDelete,
            bottomAction: TextButton(
              onPressed: _forgotPin,
              child: const Text(
                'Forgot PIN? Sign in with password',
                style: TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
