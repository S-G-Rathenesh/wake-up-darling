import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Full-screen romantic wake animation shown when partner wakes the user.
/// Displays a pulsing heart, glowing text, and an animated accept button.
/// Auto-closes after 6 seconds or when user taps "Got it 💜".
class WakeAnimationScreen extends StatefulWidget {
  final String partnerName;
  const WakeAnimationScreen({super.key, this.partnerName = 'Your partner'});

  @override
  State<WakeAnimationScreen> createState() => _WakeAnimationScreenState();
}

class _WakeAnimationScreenState extends State<WakeAnimationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-close after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A0533),
              Color(0xFF2D0A4E),
              Color(0xFF5F0A87),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Pulsing glowing heart ────────────────────────────
                ScaleTransition(
                  scale: _pulseScale,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pinkAccent.withValues(alpha: 0.6),
                          blurRadius: 50,
                          spreadRadius: 15,
                        ),
                        BoxShadow(
                          color: Colors.purpleAccent.withValues(alpha: 0.4),
                          blurRadius: 80,
                          spreadRadius: 25,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 80,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Animated message ─────────────────────────────────
                Text(
                  '${widget.partnerName} woke you up 💜',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 300.ms)
                    .slideY(begin: 0.15, end: 0, duration: 600.ms),

                const SizedBox(height: 12),

                Text(
                  'Time to rise and shine! ☀️',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 700.ms),

                const SizedBox(height: 50),

                // ── Glowing accept button ────────────────────────────
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9C27B0), Color(0xFFE040FB)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purpleAccent.withValues(alpha: 0.5),
                          blurRadius: 25,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Got it 💜',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 1200.ms)
                    .scaleXY(begin: 0.8, end: 1.0, duration: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
