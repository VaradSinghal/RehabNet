import 'package:flutter/material.dart';

/// Describes one rehabilitation exercise type.
class ExerciseInfo {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;

  const ExerciseInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// All available exercises in the AR module.
const List<ExerciseInfo> availableExercises = [
  ExerciseInfo(
    id: 'target_touch',
    name: 'Target Touch',
    subtitle: 'Reach for AR targets',
    icon: Icons.ads_click_rounded,
    color: Color(0xFF00C896),
  ),
  ExerciseInfo(
    id: 'guided_path',
    name: 'Guided Path',
    subtitle: 'Trace the path with hand',
    icon: Icons.gesture_rounded,
    color: Color(0xFF4FC3F7),
  ),
  ExerciseInfo(
    id: 'arm_raise',
    name: 'Arm Raise Reps',
    subtitle: 'Count full arm raises',
    icon: Icons.fitness_center_rounded,
    color: Color(0xFFFFAB40),
  ),
];

/// Horizontal scrolling exercise selector.
class ExerciseSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<ExerciseInfo> onSelected;

  const ExerciseSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: availableExercises.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final ex = availableExercises[i];
          final isActive = ex.id == selected;

          return GestureDetector(
            onTap: () => onSelected(ex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 130,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? ex.color.withValues(alpha: 0.15)
                    : const Color(0xFF131929),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive ? ex.color : const Color(0xFF1E2840),
                  width: isActive ? 2 : 1,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: ex.color.withValues(alpha: 0.2), blurRadius: 12)]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(ex.icon, color: ex.color, size: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex.name,
                          style: TextStyle(
                              color: isActive ? Colors.white : const Color(0xFF8892A4),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter')),
                      Text(ex.subtitle,
                          style: const TextStyle(
                              color: Color(0xFF5A6478),
                              fontSize: 10,
                              fontFamily: 'Inter')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
