import 'dart:async';
import 'package:capstone_app/Auth/login.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/main.dart' show globalNavigatorKey;

class IdleTimeoutManager {
  static final IdleTimeoutManager _instance = IdleTimeoutManager._internal();
  factory IdleTimeoutManager() => _instance;
  IdleTimeoutManager._internal();

  Timer? _timer;
  BuildContext? _context;

  void start(BuildContext context) {
    _context = context;
    _reset();
  }

  void reset() {
    _reset();
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(const Duration(minutes: 10), _onTimeout);
  }

  Future<void> _onTimeout() async {
    await Supabase.instance.client.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    await prefs.remove('selectedDayungUnitData');

    final navigator = globalNavigatorKey.currentState;
    final context = navigator?.context;

    String? currentRoute;
    Widget? currentWidget;
    navigator?.popUntil((route) {
      currentRoute = route.settings.name;
      // Try to get the widget type for fallback
      if (route is MaterialPageRoute) {
        try {
          currentWidget = route.builder(context!);
        } catch (_) {}
      }
      return true;
    });

    // Check by route name or widget type
    final isLogin = currentRoute == '/login' || currentWidget is Login;
    final isRegister = currentRoute == '/register';
    final isSplash =
        currentRoute == '/' ||
        (currentWidget?.runtimeType.toString() == 'SplashScreen');

    if (context != null && !isLogin && !isRegister && !isSplash) {
      try {
        await showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFF3B82F6),
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Signed out',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: Color(0xFF0D47A1),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You have been signed out due to inactivity.\nPlease login again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w500,
                      fontSize: 15.5,
                      color: Color(0xFF4B5563),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.of(ctx, rootNavigator: true).pop();
                      },
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.w600,
                          fontSize: 16.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (_) {}

      // After dialog, navigate to login (with route name)
      navigator!.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const Login(),
          settings: const RouteSettings(name: '/login'),
        ),
        (route) => false,
      );
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _context = null;
  }
}
