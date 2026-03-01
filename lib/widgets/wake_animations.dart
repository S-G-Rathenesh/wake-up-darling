import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Floating heart particle overlay with randomized positions, sizes, and speeds.
/// Uses pure Flutter — does NOT require Lottie or any external asset.
class FloatingHeartsParticle extends StatelessWidget {
  final int heartCount;
  const FloatingHeartsParticle({super.key, this.heartCount = 15});

  @override
  Widget build(BuildContext context) {
    final rng = Random(42);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            children: List.generate(heartCount, (i) {
              final size = 8.0 + rng.nextDouble() * 14;
              final left = rng.nextDouble() * w;
              final duration = 3000 + rng.nextInt(4000);
              final delay = rng.nextInt(3000);
              final opacity = 0.15 + rng.nextDouble() * 0.25;

              return Positioned(
                left: left,
                bottom: -20,
                child: Icon(
                  Icons.favorite,
                  size: size,
                  color: Colors.pinkAccent.withValues(alpha: opacity),
                )
                    .animate(
                      onPlay: (c) => c.repeat(),
                      delay: Duration(milliseconds: delay),
                    )
                    .moveY(
                      begin: 0,
                      end: -(h + 40),
                      duration: Duration(milliseconds: duration),
                      curve: Curves.easeOut,
                    )
                    .fadeOut(
                      begin: opacity,
                      duration: Duration(milliseconds: duration),
                    )
                    .moveX(
                      begin: 0,
                      end: (rng.nextBool() ? 1 : -1) * (10 + rng.nextDouble() * 30),
                      duration: Duration(milliseconds: duration),
                      curve: Curves.easeInOut,
                    ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Animated cute wake-up message cards.
class AnimatedWakeMessage extends StatelessWidget {
  final String message;
  final IconData icon;

  const AnimatedWakeMessage({
    super.key,
    required this.message,
    this.icon = Icons.favorite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.pinkAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .slideX(begin: -0.1, end: 0, duration: 600.ms, curve: Curves.easeOut);
  }
}

/// A Lottie‐style animation placeholder widget.
/// If a Lottie JSON is available in assets/animations/, uses it.
/// Otherwise falls back to a Flutter-native animated icon set.
class WakeAnimation extends StatelessWidget {
  final WakeAnimationType type;
  final double size;

  const WakeAnimation({
    super.key,
    required this.type,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    // Pure Flutter fallback animation (no Lottie file needed).
    return SizedBox(
      width: size,
      height: size,
      child: _buildFallbackAnimation(),
    );
  }

  Widget _buildFallbackAnimation() {
    switch (type) {
      case WakeAnimationType.partnerSetAlarm:
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.amber.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
          child: const Icon(Icons.alarm, color: Colors.amber, size: 60),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1200.ms)
            .shimmer(duration: 2000.ms, color: Colors.amber.withValues(alpha: 0.3));

      case WakeAnimationType.streakSuccess:
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.orange.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
          child: const Icon(Icons.local_fire_department, color: Colors.orange, size: 60),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.15, 1.15), duration: 1000.ms)
            .rotate(begin: -0.02, end: 0.02, duration: 800.ms);

      case WakeAnimationType.emergencyWake:
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.redAccent.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
          child: const Icon(Icons.warning_amber, color: Colors.redAccent, size: 60),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shake(duration: 600.ms, hz: 3)
            .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 800.ms);

      case WakeAnimationType.voiceWake:
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.pinkAccent.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
          child: const Icon(Icons.mic, color: Colors.pinkAccent, size: 60),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1500.ms)
            .fadeIn();
    }
  }
}

enum WakeAnimationType {
  partnerSetAlarm,
  streakSuccess,
  emergencyWake,
  voiceWake,
}
