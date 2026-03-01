import 'dart:ui';

import 'package:flutter/material.dart';

/// A glass-morphism card with frosted backdrop blur, subtle white border,
/// and an optional animated shimmer highlight.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.margin,
    this.sigmaX = 18,
    this.sigmaY = 18,
    this.backgroundColor,
    this.borderColor,
    this.shimmer = true,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double sigmaX;
  final double sigmaY;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool shimmer;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    if (widget.shimmer) _shimmerController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: widget.sigmaX, sigmaY: widget.sigmaY),
          child: AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              final shimmerOpacity =
                  widget.shimmer ? _shimmerController.value * 0.06 : 0.0;
              return Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: (widget.backgroundColor ??
                          Colors.white.withValues(alpha: 0.07))
                      .withValues(
                    alpha: 0.07 + shimmerOpacity,
                  ),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: widget.borderColor ??
                        Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
