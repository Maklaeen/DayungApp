import 'package:capstone_app/Auth/pin_pad_widget.dart';
import 'package:capstone_app/Auth/pin_service.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final List<String> _digits = [];
  List<String>? _firstPin;
  bool _isConfirming = false;
  String? _error;

  void _onDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() {
      _digits.add(d);
      _error = null;
    });
    if (_digits.length == 4) _onComplete();
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _onComplete() async {
    final pin = _digits.join();
    if (!_isConfirming) {
      setState(() {
        _firstPin = List.from(_digits);
        _digits.clear();
        _isConfirming = true;
      });
    } else {
      if (pin == _firstPin!.join()) {
        final uid = Supabase.instance.client.auth.currentUser!.id;
        await PinService.savePin(uid, pin);
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _digits.clear();
          _firstPin = null;
          _isConfirming = false;
          _error = 'PINs do not match. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Set Up PIN'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: PinPad(
        title: _isConfirming ? 'Confirm your PIN' : 'Create a 4-digit PIN',
        subtitle: _isConfirming
            ? 'Enter your PIN again to confirm'
            : 'You\'ll use this to unlock the app',
        filledCount: _digits.length,
        error: _error,
        onDigit: _onDigit,
        onDelete: _onDelete,
      ),
    );
  }
}
