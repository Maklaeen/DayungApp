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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0F4F8), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double screenWidth = constraints.maxWidth;
                    double screenHeight = constraints.maxHeight;
                    double maxSize = screenWidth < screenHeight
                        ? screenWidth
                        : screenHeight;
                    double animationSize = maxSize * 0.5;

                    return Center(
                      child:
                          SizedBox(
                                width: animationSize,
                                height: animationSize,
                                child: Lottie.asset(
                                  'assets/animation/Handshake animation.json',
                                  fit: BoxFit.contain,
                                  repeat: true,
                                  animate: true,
                                ),
                              )
                              .animate()
                              .fadeIn(duration: 1.2.seconds, delay: 300.ms)
                              .scale(
                                begin: const Offset(1.0, 1.0),
                                end: const Offset(1.2, 1.2),
                                duration: 1.seconds,
                                delay: 3.seconds,
                                curve: Curves.easeInOut,
                              ),
                    );
                  },
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 30),
                    Text(
                          'Dayung',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                            letterSpacing: 1.2,
                            fontFamily: 'Montserrat',
                          ),
                          textAlign: TextAlign.center,
                        )
                        .animate(delay: 1.5.seconds)
                        .fadeIn(duration: 1.seconds)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 800.ms,
                          curve: Curves.easeOut,
                        ),
                    const SizedBox(height: 8),
                    Text(
                          'Tabang sa kalisud, Sa isa ka Tap',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: kNeutralText.withValues(alpha: 0.8),
                            letterSpacing: 0.5,
                            fontFamily: 'OpenSans',
                          ),
                          textAlign: TextAlign.center,
                        )
                        .animate(delay: 1.8.seconds)
                        .fadeIn(duration: 800.ms)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 600.ms,
                          curve: Curves.easeOut,
                        ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 8,
                            shadowColor: kPrimary.withValues(alpha: 0.3),
                          ),
                          child: const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                        )
                        .animate(delay: 2.seconds)
                        .fadeIn(duration: 1.seconds)
                        .slideY(
                          begin: 0.3,
                          end: 0,
                          duration: 1.seconds,
                          curve: Curves.easeOutBack,
                        )
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1.0, 1.0),
                          duration: 800.ms,
                          curve: Curves.elasticOut,
                        )
                        .then()
                        .scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.05, 1.05),
                          duration: 1.2.seconds,
                          delay: 3.seconds,
                          curve: Curves.easeInOut,
                        )
                        .then()
                        .scale(
                          begin: const Offset(1.05, 1.05),
                          end: const Offset(1.0, 1.0),
                          duration: 1.2.seconds,
                          curve: Curves.easeInOut,
                        )
                        .then()
                        .scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.05, 1.05),
                          duration: 1.2.seconds,
                          curve: Curves.easeInOut,
                        )
                        .then()
                        .scale(
                          begin: const Offset(1.05, 1.05),
                          end: const Offset(1.0, 1.0),
                          duration: 1.2.seconds,
                          curve: Curves.easeInOut,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
