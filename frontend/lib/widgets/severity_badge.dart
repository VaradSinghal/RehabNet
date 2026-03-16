/// Animated severity badge pill: Low / Moderate / High
/// Pulses with a glow effect at High severity.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SeverityBadge extends StatelessWidget {
  final String label;   // "Low" | "Moderate" | "High"

  const SeverityBadge({super.key, required this.label});

  Color get _color {
    switch (label) {
      case 'High':     return const Color(0xFFFF5252);
      case 'Moderate': return const Color(0xFFFFAB40);
      default:         return const Color(0xFF00C896);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = _color;
    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.15),
        border: Border.all(color: col, width: 1.5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: label == 'High'
            ? [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 2)]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: col,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );

    // Pulsing glow for High severity
    if (label == 'High') {
      badge = badge.animate(onPlay: (c) => c.repeat()).scaleXY(
            begin: 1.0,
            end: 1.04,
            duration: 700.ms,
            curve: Curves.easeInOut,
          );
    }

    return badge;
  }
}
