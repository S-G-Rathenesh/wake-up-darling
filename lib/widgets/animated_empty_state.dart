import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Animated empty-state placeholder with a pulsing icon and fading message.
/// Used when lists or galleries have no content yet.
class AnimatedEmptyState extends StatelessWidget {
  const AnimatedEmptyState({
    super.key,
    this.icon = Icons.favorite_border,
    this.message = 'Nothing here yet',
    this.iconSize = 72,
  });

  final IconData icon;
  final String message;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing icon with glow
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1.0, end: 1.08, duration: 1800.ms, curve: Curves.easeInOut)
              .fade(begin: 0.7, end: 1.0, duration: 1800.ms),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(duration: 600.ms, delay: 200.ms)
              .slideY(begin: 0.15, end: 0, duration: 500.ms),
        ],
      ),
    );
  }
}
