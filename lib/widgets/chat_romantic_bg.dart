import 'dart:math';
import 'package:flutter/material.dart';

/// A romantic chat background with tiny floating hearts, sparkles,
/// and a soft gradient shimmer. Designed to sit behind message bubbles
/// without being distracting. Ignores all pointer events.
class ChatRomanticBackground extends StatefulWidget {
  const ChatRomanticBackground({super.key});

  @override
  State<ChatRomanticBackground> createState() => _ChatRomanticBackgroundState();
}

class _ChatRomanticBackgroundState extends State<ChatRomanticBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _RomanticPainter(_controller.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _RomanticPainter extends CustomPainter {
  final double progress;
  _RomanticPainter(this.progress);

  // Pre-defined particles for consistent look
  static final List<_Particle> _particles = List.generate(18, (i) {
    final rng = Random(i * 7 + 3);
    return _Particle(
      x: rng.nextDouble(),
      startY: 0.8 + rng.nextDouble() * 0.3,
      speed: 0.15 + rng.nextDouble() * 0.25,
      size: 3.0 + rng.nextDouble() * 5.0,
      opacity: 0.04 + rng.nextDouble() * 0.06,
      isHeart: rng.nextBool(),
      drift: (rng.nextDouble() - 0.5) * 0.05,
      phase: rng.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress + p.phase) % 1.0;
      final y = size.height * (p.startY - t * p.speed * 4);
      if (y < -20 || y > size.height + 20) continue;

      final x = size.width * p.x + sin(t * 2 * pi) * size.width * p.drift;

      // Fade in at bottom, fade out at top
      final fadeY = 1.0 - ((size.height - y) / size.height).clamp(0.0, 1.0);
      final alpha = p.opacity * (1.0 - fadeY * fadeY);

      if (p.isHeart) {
        _drawHeart(canvas, x, y, p.size, alpha);
      } else {
        _drawSparkle(canvas, x, y, p.size * 0.6, alpha, t);
      }
    }
  }

  void _drawHeart(Canvas canvas, double x, double y, double size, double alpha) {
    final paint = Paint()
      ..color = Colors.pinkAccent.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    final path = Path();
    final s = size;
    path.moveTo(x, y + s * 0.3);
    path.cubicTo(x - s * 0.5, y - s * 0.2, x - s * 0.5, y + s * 0.6, x, y + s * 0.85);
    path.cubicTo(x + s * 0.5, y + s * 0.6, x + s * 0.5, y - s * 0.2, x, y + s * 0.3);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSparkle(Canvas canvas, double x, double y, double size, double alpha, double t) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha * 1.2)
      ..style = PaintingStyle.fill;

    // Pulsing sparkle
    final pulse = 0.7 + 0.3 * sin(t * 4 * pi);
    final r = size * pulse;

    // 4-point star
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      final outerX = x + cos(angle) * r;
      final outerY = y + sin(angle) * r;
      final innerAngle = angle + pi / 4;
      final innerX = x + cos(innerAngle) * r * 0.3;
      final innerY = y + sin(innerAngle) * r * 0.3;
      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RomanticPainter old) => old.progress != progress;
}

class _Particle {
  final double x;
  final double startY;
  final double speed;
  final double size;
  final double opacity;
  final bool isHeart;
  final double drift;
  final double phase;

  const _Particle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.isHeart,
    required this.drift,
    required this.phase,
  });
}
