import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Providers/role_router.dart';

// --- Color constants (copy from profile.dart or import if shared) ---
const kAccent = Color(0xFF059669);
const kPrimary = Color(0xFF3B82F6);
const kWarn = Color(0xFFF59E0B);
const kText = Color(0xFF111827);


class PinLock {
  static const _kKey = 'user_pin_hash';
  static final _storage = const FlutterSecureStorage();

  static Future<void> ensureUnlockAndRouteHome(BuildContext context) async {
    // If no session, just return and let your normal flow (login) handle it
    if (Supabase.instance.client.auth.currentSession == null) return;

    // If there is a PIN, ask for it; otherwise continue
    bool proceed = true;
    if (await hasPin()) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const UnlockPinPage()),
      );
      proceed = ok == true;
    }
    if (!proceed) return;
    await _routeHomeFromContext(context);
  }

  static Future<void> _routeHomeFromContext(BuildContext context) async {
    // Rehydrate selection and roles
    final unitProv = context.read<DayungUnitProvider>();
    await unitProv.loadDayungUnit();
    final unitId = unitProv.currentUnitId ?? unitProv.dayungUnitObj?['id'] as int?;
    await context.read<DayungRoleProvider>().refreshRoles(unitId);

    // Route via RoleRouter (it will decide the correct dashboard)
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleRouter()),
      (route) => false,
    );
  }

  static Future<bool> hasPin() async {
    final v = await _storage.read(key: _kKey);
    return v != null && v.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final h = pin.hashCode.toString();
    await _storage.write(key: _kKey, value: h);
  }

  static Future<bool> verify(String pin) async {
    final h = await _storage.read(key: _kKey);
    return h == pin.hashCode.toString();
  }

  static Future<bool> ensurePinSetup(BuildContext context) async {
    if (!await hasPin()) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const SetPinPage()),
      );
      return ok == true;
    }
    return true;
  }

  static Future<bool> guard(BuildContext context) async {
    if (Supabase.instance.client.auth.currentSession == null) return true;
    if (!await hasPin()) return true;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const UnlockPinPage()),
    );
    return ok == true;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kKey);
  }
}

class SetPinPage extends StatefulWidget {
  final bool canSkip;
  const SetPinPage({super.key, this.canSkip = false});
  @override
  State<SetPinPage> createState() => _SetPinPageState();
}

class _SetPinPageState extends State<SetPinPage> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p1 = _c1.text.trim();
    final p2 = _c2.text.trim();
    if (p1.length != 6 || p2.length != 6) {
      setState(() => _err = 'PIN must be 6 digits.');
      return;
    }
    if (p1 != p2) {
      setState(() => _err = 'PINs do not match.');
      return;
    }
    setState(() => _saving = true);
    await PinLock.setPin(p1);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  InputDecoration _dec(String label, {bool error = false}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: error ? kWarn : const Color(0xFFE5E7EB),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error ? kWarn : kAccent, width: 2),
      ),
      errorText: null,
    );
  }

  Widget _errRow(String msg) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: kWarn, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(color: kWarn, fontSize: 13.5, height: 1.2),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Set App PIN'),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.canSkip)
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text(
                'Skip',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12.withOpacity(0.45)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 18,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon and title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.pin_rounded, color: kAccent),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Set App PIN',
                        style: TextStyle(
                          color: kText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _c1,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: _dec('Enter 6-digit PIN', error: _err != null),
                  onChanged: (_) => setState(() => _err = null),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _c2,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: _dec('Confirm PIN', error: _err != null),
                  onChanged: (_) => setState(() => _err = null),
                ),
                if (_err != null) _errRow(_err!),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Save PIN',
                            style: TextStyle(
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
    );
  }
}

class UnlockPinPage extends StatefulWidget {
  const UnlockPinPage({super.key});
  @override
  State<UnlockPinPage> createState() => _UnlockPinPageState();
}

class _UnlockPinPageState extends State<UnlockPinPage> {
  final _c = TextEditingController();
  String? _err;
  bool _verifying = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _err = null;
    });
    final ok = await PinLock.verify(_c.text.trim());
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _err = 'Incorrect PIN.');
    }
  }

  InputDecoration _dec(String label, {bool error = false}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: error ? kWarn : const Color(0xFFE5E7EB),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error ? kWarn : kAccent, width: 2),
      ),
      errorText: null,
    );
  }

  Widget _errRow(String msg) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: kWarn, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(color: kWarn, fontSize: 13.5, height: 1.2),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Enter App PIN'),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12.withOpacity(0.45)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 18,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon and title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock, color: kAccent),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Enter App PIN',
                        style: TextStyle(
                          color: kText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _c,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: _dec('Enter 6-digit PIN', error: _err != null),
                  onChanged: (_) => setState(() => _err = null),
                  onSubmitted: (_) => _verify(),
                ),
                if (_err != null) _errRow(_err!),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _verifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _verifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Unlock',
                            style: TextStyle(
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
    );
  }
}