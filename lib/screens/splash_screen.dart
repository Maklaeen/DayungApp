import 'package:capstone_app/Auth/idle_timeout_manage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    IdleTimeoutManager().start(context);
  }

  void _goToLogin() {
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildBackdropOrb({
    required double size,
    required Alignment alignment,
    required List<Color> colors,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: colors),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroAnimation(double size) {
    return Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.9),
                Colors.white.withValues(alpha: 0.72),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.75),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withValues(alpha: 0.12),
                blurRadius: 48,
                offset: const Offset(0, 24),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(-8, -8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * 0.74,
                height: size * 0.74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      kPrimary.withValues(alpha: 0.14),
                      kPrimary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
              Lottie.asset(
                'assets/animation/hands.json',
                fit: BoxFit.contain,
                repeat: false,
                animate: true,
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 900.ms, delay: 150.ms)
        .slideY(
          begin: -0.06,
          end: 0,
          duration: 900.ms,
          curve: Curves.easeOutCubic,
        )
        .scale(
          begin: const Offset(0.94, 0.94),
          end: const Offset(1, 1),
          duration: 900.ms,
        )
        .shimmer(
          duration: 2200.ms,
          color: Colors.white.withValues(alpha: 0.22),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FAFC), Color(0xFFE9EEF7), Color(0xFFDCE6F2)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final compact = screenHeight < 760;
            final heroSize =
                screenWidth.clamp(280.0, 380.0) * (compact ? 0.78 : 0.86);
            final contentWidth = screenWidth > 460 ? 420.0 : screenWidth - 40;

            return Stack(
              children: [
                _buildBackdropOrb(
                  size: screenWidth * 0.72,
                  alignment: const Alignment(-1.15, -0.92),
                  colors: [
                    kPrimary.withValues(alpha: 0.16),
                    kPrimary.withValues(alpha: 0.02),
                    Colors.transparent,
                  ],
                ),
                _buildBackdropOrb(
                  size: screenWidth * 0.9,
                  alignment: const Alignment(1.12, -0.28),
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.transparent,
                  ],
                ),
                _buildBackdropOrb(
                  size: screenWidth * 0.8,
                  alignment: const Alignment(0.0, 1.18),
                  colors: [
                    kAccent.withValues(alpha: 0.1),
                    kAccent.withValues(alpha: 0.02),
                    Colors.transparent,
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentWidth),
                        child: Column(
                          children: [
                            const Spacer(flex: 3),
                            Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  // decoration: BoxDecoration(
                                  //   color: Colors.white.withValues(alpha: 0.62),
                                  //   borderRadius: BorderRadius.circular(999),
                                  //   border: Border.all(
                                  //     color: Colors.white.withValues(
                                  //       alpha: 0.85,
                                  //     ),
                                  //   ),
                                  // ),
                                  // child: Text(
                                  //   'Community assistance, simplified',
                                  //   style: TextStyle(
                                  //     color: kPrimaryDark.withValues(
                                  //       alpha: 0.9,
                                  //     ),
                                  //     fontSize: 12,
                                  //     fontWeight: FontWeight.w700,
                                  //     letterSpacing: 0.6,
                                  //     fontFamily: 'OpenSans',
                                  //   ),
                                  // ),
                                )
                                .animate()
                                .fadeIn(duration: 600.ms)
                                .slideY(begin: -0.25, end: 0, duration: 700.ms),
                            SizedBox(height: compact ? 18 : 26),
                            _buildHeroAnimation(heroSize),
                            SizedBox(height: compact ? 24 : 34),
                            Text(
                                  'Dayung',
                                  style: TextStyle(
                                    fontSize: compact ? 40 : 46,
                                    fontWeight: FontWeight.w800,
                                    color: kPrimary,
                                    letterSpacing: 0.4,
                                    fontFamily: 'Montserrat',
                                    height: 0.95,
                                  ),
                                  textAlign: TextAlign.center,
                                )
                                .animate(delay: 250.ms)
                                .fadeIn(duration: 700.ms)
                                .slideY(begin: 0.16, end: 0, duration: 700.ms),
                            const SizedBox(height: 10),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child:
                                  Text(
                                        'Tabang sa kalisud, sa isa ka tap.',
                                        style: TextStyle(
                                          fontSize: compact ? 15 : 16,
                                          fontWeight: FontWeight.w600,
                                          color: kNeutralText.withValues(
                                            alpha: 0.7,
                                          ),
                                          letterSpacing: 0.1,
                                          fontFamily: 'OpenSans',
                                          height: 1.45,
                                        ),
                                        textAlign: TextAlign.center,
                                      )
                                      .animate(delay: 420.ms)
                                      .fadeIn(duration: 700.ms)
                                      .slideY(
                                        begin: 0.18,
                                        end: 0,
                                        duration: 700.ms,
                                      ),
                            ),
                            const Spacer(flex: 2),
                            SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _goToLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      elevation: 0,
                                      shadowColor: Colors.transparent,
                                    ),
                                    child: const Text(
                                      'Get Started',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                  ),
                                )
                                .animate(delay: 650.ms)
                                .fadeIn(duration: 700.ms)
                                .slideY(begin: 0.24, end: 0, duration: 700.ms)
                                .scale(
                                  begin: const Offset(0.96, 0.96),
                                  end: const Offset(1, 1),
                                  duration: 700.ms,
                                ),
                            const SizedBox(height: 14),
                            // Text(
                            //   'Secure barangay assistance workflow',
                            //   style: TextStyle(
                            //     fontSize: 12,
                            //     fontWeight: FontWeight.w600,
                            //     color: kSubtleText.withValues(alpha: 0.7),
                            //     letterSpacing: 0.25,
                            //     fontFamily: 'OpenSans',
                            //   ),
                            // ).animate(delay: 800.ms).fadeIn(duration: 600.ms),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
