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
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                isWide ? 32 : 20,
                isWide ? 28 : 20,
                isWide ? 32 : 20,
                isWide ? 28 : 20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Set Up PIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Secure your account with a 4-digit PIN',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Step indicator
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
              child: Row(
                children: [
                  _StepDot(active: true, done: _isConfirming, label: '1'),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: _isConfirming
                          ? kPrimary
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  _StepDot(active: _isConfirming, done: false, label: '2'),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            // PIN pad
            Expanded(
              child: PinPad(
                title: _isConfirming ? 'Confirm your PIN' : 'Create a PIN',
                subtitle: _isConfirming
                    ? 'Enter the same PIN again to confirm'
                    : 'Choose a 4-digit PIN you\'ll remember',
                filledCount: _digits.length,
                error: _error,
                onDigit: _onDigit,
                onDelete: _onDelete,
                topContent: _StepLabel(isConfirming: _isConfirming),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;

  const _StepDot({
    required this.active,
    required this.done,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active || done ? kPrimary : const Color(0xFFE2E8F0),
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
            : Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : kSubtleText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                ),
              ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  final bool isConfirming;
  const _StepLabel({required this.isConfirming});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirming
                ? Icons.check_circle_outline_rounded
                : Icons.lock_outline_rounded,
            color: kPrimary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isConfirming ? 'Step 2 of 2 — Confirm PIN' : 'Step 1 of 2 — Create PIN',
            style: const TextStyle(
              color: kPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
          ),
        ],
      ),
    );
  }
}
