import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after total 5s animation
    Future.delayed(5.seconds, () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFFFAFAF9);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Single image animation (slide from top + fade in)
            SizedBox(
              width: 260,
              height: 180,
              child: Center(
                child:
                    Image.asset(
                          'assets/images/iconApp.jpeg',
                          width: 260,
                          fit: BoxFit.contain,
                        )
                        .animate()
                        .moveY(
                          begin: -220,
                          end: 0,
                          duration: 3.seconds,
                          curve: Curves.easeOutBack,
                        )
                        .fadeIn(duration: 800.ms),
              ),
            ),
            const SizedBox(height: 20),

            // Slogan (fade in after image settles)
            const Text(
              'Tabang sa Kalisud, Sa isa ka Tap.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ).animate(delay: 3.seconds).fadeIn(duration: 1.seconds),

            const SizedBox(height: 12),

            // Loading indicator (fade in last)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ).animate(delay: 4.seconds).fadeIn(duration: 1.seconds),
          ],
        ),
      ),
    );
  }
}
