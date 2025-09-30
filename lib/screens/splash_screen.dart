// ...existing code...
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
// ...existing code...

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

// Make the state a ticker provider for our animation controller
class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _handsCtl;

  @override
  void initState() {
    super.initState();

    _handsCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Navigate after total 5s animation
    Future.delayed(6.seconds, () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _handsCtl.dispose();
    super.dispose();
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
            // Animated hands (asset-free)
            SizedBox(
                  width: 260,
                  height: 180,
                  child: _AnimatedHands(animation: _handsCtl),
                )
                // Subtle entrance like before
                .animate()
                .moveY(
                  begin: -220,
                  end: 0,
                  duration: 3.seconds,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 800.ms),

            const SizedBox(height: 20),

            // Slogan (fade in after hands settle)
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

// Animated, asset-free “hands” using Material icons and transforms
class _AnimatedHands extends StatelessWidget {
  final Animation<double> animation;
  const _AnimatedHands({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        // Wave between -1..1
        final t = sin(animation.value * 2 * 3.141592653589793);
        // Angles in radians
        final leftAngle = lerpDouble(-0.50, -0.15, (t + 1) / 2)!;
        final rightAngle = lerpDouble(0.50, 0.15, (t + 1) / 2)!;
        // Small inwards slide
        final inwards = 6.0 + 4.0 * (1 - (t.abs()));

        return Stack(
          alignment: Alignment.center,
          children: [
            // Left hand
            Transform.translate(
              offset: Offset(inwards, 6),
              child: Transform.rotate(
                angle: leftAngle,
                alignment: Alignment.bottomRight,
                child: Icon(
                  Icons.front_hand_rounded,
                  size: 92,
                  color: Colors.amber[700],
                ),
              ),
            ),
            // Right hand (mirrored)
            Transform.translate(
              offset: Offset(-inwards, 6),
              child: Transform(
                alignment: Alignment.bottomLeft,
                transform: Matrix4.identity()
                  ..rotateZ(rightAngle)
                  ..scale(-1.0, 1.0, 1.0), // mirror horizontally
                child: Icon(
                  Icons.front_hand_rounded,
                  size: 92,
                  color: Colors.amber[600],
                ),
              ),
            ),
            // Heart pulse between hands (tiny, breathing)
            Opacity(
              opacity: (0.35 + 0.25 * (t.abs())).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.9 + 0.08 * (t.abs()),
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 24,
                  color: Color(0xFFE91E63),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Simple double lerp helper
  double? lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
