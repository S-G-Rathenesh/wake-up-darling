import 'package:flutter/material.dart';

/// A full-screen animated gradient background that slowly cycles through
/// deep purple hues.  Lightweight — uses a single [AnimationController]
/// and [AnimatedBuilder] with no extra allocations per frame.
class AnimatedGradientBackground extends StatefulWidget {
  const AnimatedGradientBackground({super.key});

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Three gradient stops — we interpolate between two palettes.
  static const _colorsA = [Color(0xFF7B2FF7), Color(0xFF5F0A87), Color(0xFF9D4EDD)];
  static const _colorsB = [Color(0xFF9D4EDD), Color(0xFF7B2FF7), Color(0xFF4A00E0)];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(_colorsA[0], _colorsB[0], t)!,
                Color.lerp(_colorsA[1], _colorsB[1], t)!,
                Color.lerp(_colorsA[2], _colorsB[2], t)!,
              ],
            ),
          ),
        );
      },
    );
  }
}
