/// Animated feedback banner that slides in from top, shows a message,
/// then auto-dismisses after 2.5 seconds.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FeedbackBanner extends StatelessWidget {
  final String message;
  final bool isPositive;

  const FeedbackBanner({
    super.key,
    required this.message,
    this.isPositive = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPositive
        ? const Color(0xFF00C896)   // mint green
        : const Color(0xFFFF5252);  // red

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isPositive ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: -0.2, end: 0, duration: 300.ms);
  }
}

/// Overlay helper: shows a FeedbackBanner at the top of the screen for 2.5 s.
void showFeedback(BuildContext context, String message, {bool positive = true}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: FeedbackBanner(message: message, isPositive: positive),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2500), entry.remove);
}
