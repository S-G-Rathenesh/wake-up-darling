import 'dart:math';
import 'package:flutter/material.dart';

/// Animated voice wave bars — 5 vertical bars with random heights that loop.
/// Used on the call screen to visualise active audio.
class VoiceWaveBars extends StatefulWidget {
  final Color color;
  final double barWidth;
  final double maxHeight;
  final int barCount;

  const VoiceWaveBars({
    super.key,
    this.color = Colors.white,
    this.barWidth = 4,
    this.maxHeight = 40,
    this.barCount = 5,
  });

  @override
  State<VoiceWaveBars> createState() => _VoiceWaveBarsState();
}

class _VoiceWaveBarsState extends State<VoiceWaveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _random = Random();
  late List<double> _heights;

  @override
  void initState() {
    super.initState();
    _heights = List.generate(widget.barCount, (_) => _nextHeight());
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _heights = List.generate(widget.barCount, (_) => _nextHeight());
          });
          _controller.forward(from: 0);
        }
      });
    _controller.forward();
  }

  double _nextHeight() =>
      widget.maxHeight * 0.2 + _random.nextDouble() * widget.maxHeight * 0.8;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.barWidth * 0.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                width: widget.barWidth,
                height: _heights[i],
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(widget.barWidth),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
