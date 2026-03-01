import 'package:flutter/material.dart';

/// Custom animated bottom navigation bar with scale + glow on selection
/// and a sliding indicator dot.
class AnimatedBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AnimatedNavItem> items;

  const AnimatedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 72 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC4A00E0), Color(0xFF2A0845)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final selected = i == currentIndex;
            final item = items[i];
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Icon with scale + glow ──────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.purpleAccent
                                      .withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [],
                      ),
                      child: AnimatedScale(
                        scale: selected ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        child: Badge(
                          isLabelVisible: item.badgeCount > 0,
                          label: Text(
                            '${item.badgeCount}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          child: Icon(
                            selected ? item.activeIcon : item.icon,
                            color: selected ? Colors.white : Colors.white54,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),

                    // ── Label ────────────────────────────────────────
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white54,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                        fontSize: selected ? 12 : 11,
                      ),
                      child: Text(item.label),
                    ),
                    const SizedBox(height: 3),

                    // ── Indicator dot ────────────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: selected ? 6 : 0,
                      height: selected ? 6 : 0,
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent,
                        shape: BoxShape.circle,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.purpleAccent
                                      .withValues(alpha: 0.6),
                                  blurRadius: 8,
                                ),
                              ]
                            : [],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ),
    );
  }
}

/// Data class for each navigation item.
class AnimatedNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;

  const AnimatedNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}
