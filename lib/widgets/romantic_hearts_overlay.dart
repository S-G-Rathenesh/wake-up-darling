import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A lightweight overlay of softly floating hearts.
/// Wrap the screen's [Scaffold.body] in a [Stack] and place this on top.
/// The widget ignores all pointer events so it never blocks interactions.
class RomanticHeartsOverlay extends StatelessWidget {
  const RomanticHeartsOverlay({super.key});

  static const _configs = <_HeartConfig>[
    _HeartConfig(leftFraction: 0.05, delayMs: 0,    size: 14, durationMs: 4200),
    _HeartConfig(leftFraction: 0.15, delayMs: 1200, size: 10, durationMs: 3800),
    _HeartConfig(leftFraction: 0.28, delayMs: 600,  size: 16, durationMs: 4600),
    _HeartConfig(leftFraction: 0.42, delayMs: 1800, size: 12, durationMs: 3600),
    _HeartConfig(leftFraction: 0.55, delayMs: 300,  size: 18, durationMs: 5000),
    _HeartConfig(leftFraction: 0.68, delayMs: 900,  size: 11, durationMs: 3900),
    _HeartConfig(leftFraction: 0.78, delayMs: 1500, size: 15, durationMs: 4400),
    _HeartConfig(leftFraction: 0.90, delayMs: 450,  size:  9, durationMs: 3500),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final travelY = constraints.maxHeight * 0.75;
          return Stack(
            children: _configs.map((h) {
              return Positioned(
                left: constraints.maxWidth * h.leftFraction,
                bottom: 40,
                child: Icon(
                  Icons.favorite,
                  size: h.size.toDouble(),
                  color: Colors.white.withValues(alpha: 0.08),
                )
                    .animate(
                      onPlay: (c) => c.repeat(),
                      delay: Duration(milliseconds: h.delayMs),
                    )
                    .moveY(
                      begin: 0,
                      end: -travelY,
                      duration: Duration(milliseconds: h.durationMs),
                      curve: Curves.easeOut,
                    )
                    .fadeOut(
                      begin: 0.20,
                      duration: Duration(milliseconds: h.durationMs),
                    ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _HeartConfig {
  final double leftFraction;
  final int delayMs;
  final int size;
  final int durationMs;
  const _HeartConfig({
    required this.leftFraction,
    required this.delayMs,
    required this.size,
    required this.durationMs,
  });
}
