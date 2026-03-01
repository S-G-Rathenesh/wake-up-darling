import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Animated typing indicator with 3 bouncing/fading dots.
/// Shows a subtle slide-up when it appears.
class TypingDots extends StatelessWidget {
  final Color color;
  final double dotSize;

  const TypingDots({
    super.key,
    this.color = Colors.white70,
    this.dotSize = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          )
              .animate(
                onPlay: (c) => c.repeat(),
                delay: Duration(milliseconds: i * 200),
              )
              .scaleXY(
                begin: 0.8,
                end: 1.2,
                duration: 500.ms,
                curve: Curves.easeInOut,
              )
              .then()
              .scaleXY(
                begin: 1.2,
                end: 0.8,
                duration: 500.ms,
                curve: Curves.easeInOut,
              ),
        );
      }),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.3, end: 0, duration: 300.ms);
  }
}
