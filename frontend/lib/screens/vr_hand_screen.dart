/// VR Hand Interaction Screen
/// Renders a pseudo-3D perspective environment ("tunnel").
/// Virtual targets (spheres) approach the viewer.
/// The user drags a virtual "hand" (cursor) around the screen to
/// intercept the targets as they get close.
/// In real deployment, this would use a wearable IMU for the hand position.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class VrHandScreen extends StatefulWidget {
  const VrHandScreen({super.key});
  @override
  State<VrHandScreen> createState() => _VrHandScreenState();
}

class _VrHandScreenState extends State<VrHandScreen>
    with SingleTickerProviderStateMixin {
  // Game clock
  late Timer _timer;
  bool _running = false;

  // Player hand (using screen touches/dragging)
  double _handX = 0.5; // Normalized 0..1
  double _handY = 0.5; // Normalized 0..1

  // Metrics
  int _score = 0;
  int _missed = 0;

  // Active targets approaching in 3D
  // { x: -1..1 (left/right off center), y: -1..1 (up/down), z: 0..1 (0=far, 1=hit plane) }
  final List<_Target3D> _targets = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    setState(() { _running = true; });
    _timer = Timer.periodic(const Duration(milliseconds: 32), _gameLoop); // ~30 fps
  }

  void _gameLoop(Timer t) {
    if (!mounted || !_running) return;

    setState(() {
      // Spawn new targets randomly
      if (_targets.isEmpty || (_targets.last.z > 0.4 && _rng.nextDouble() < 0.3)) {
         _targets.add(_Target3D(
            x: (_rng.nextDouble() * 2) - 1.0, // -1 to 1
            y: (_rng.nextDouble() * 2) - 1.0, // -1 to 1
            z: 0.0,
         ));
      }

      // Move targets toward viewer
      for (int i = _targets.length - 1; i >= 0; i--) {
        final tgt = _targets[i];
        tgt.z += 0.015; // Approach speed

        // Check if it reached the "hit plane" (Z â‰ˆ 0.9 to 1.1)
        if (tgt.z >= 0.90 && tgt.z <= 1.1) {
          // Check intersection with hand
          // Map hand 0..1 to -1..1 to match target coordinate space
          final hx = (_handX * 2) - 1.0;
          final hy = (_handY * 2) - 1.0;

          // Simple distance check
          final dx = tgt.x - hx;
          final dy = tgt.y - hy;
          final distSq = dx*dx + dy*dy;

          if (distSq < 0.15) { // Hit radius
            _score++;
            _targets.removeAt(i);
            continue;
          }
        }

        // Passed the player entirely
        if (tgt.z > 1.2) {
          _missed++;
          _targets.removeAt(i);
        }
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final size = MediaQuery.of(context).size;
    setState(() {
      _handX = (_handX + details.delta.dx / size.width).clamp(0.0, 1.0);
      _handY = (_handY + details.delta.dy / size.height).clamp(0.0, 1.0);
    });
  }

  void _onPanDown(DragDownDetails details) {
    final size = MediaQuery.of(context).size;
    setState(() {
      _handX = (details.globalPosition.dx / size.width).clamp(0.0, 1.0);
      _handY = (details.globalPosition.dy / size.height).clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onPanDown: _onPanDown,
        onPanUpdate: _onPanUpdate,
        // Using a completely custom hit test behavior so touches anywhere register
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 3D Environment
            CustomPaint(
              painter: _VrEnvironmentPainter(targets: _targets),
            ),
            
            // Player Virtual Hand / Cursor
            Positioned(
              left: MediaQuery.of(context).size.width * _handX - 35,
              top: MediaQuery.of(context).size.height * _handY - 35,
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  border: Border.all(color: const Color(0xFF00C896), width: 3),
                  boxShadow: [BoxShadow(color: const Color(0xFF00C896).withValues(alpha: 0.5), blurRadius: 15)],
                ),
                child: const Icon(Icons.pan_tool, color: Color(0xFF00C896), size: 30),
              ),
            ),

            // Top HUD
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8, left: 20, right: 20, bottom: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    BackButton(color: Colors.white, onPressed: () => Navigator.pop(context)),
                    Column(
                      children: [
                        const Text('VR HAND INTERACTION', 
                          style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Inter', letterSpacing: 1.5)),
                        Text('Score: $_score', 
                          style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Missed', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Inter')),
                        Text('$_missed', style: const TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Instruction
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Column(
                children: [
                  Icon(Icons.touch_app_rounded, color: Colors.white.withValues(alpha: 0.3), size: 30),
                  const SizedBox(height: 6),
                  Text('Drag finger to move hand and catch targets', 
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontFamily: 'Inter', fontSize: 13, letterSpacing: 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Target3D {
  double x, y, z;
  _Target3D({required this.x, required this.y, required this.z});
}

// â”€â”€ Environment CustomPainter â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _VrEnvironmentPainter extends CustomPainter {
  final List<_Target3D> targets;
  _VrEnvironmentPainter({required this.targets});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060D1F), Color(0xFF040A1A), Color(0xFF02050D)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final vp = Offset(cx, cy); // Center vanishing point
    final gridPaint = Paint()..color = const Color(0xFF1A3A6A).withValues(alpha: 0.3)..strokeWidth = 1;

    // Perspective Lines (tunnel effect)
    for (int i = 0; i < 12; i++) {
        final angle = (i / 12) * math.pi * 2;
        final dx = math.cos(angle) * size.width;
        final dy = math.sin(angle) * size.height;
        canvas.drawLine(vp, Offset(cx + dx, cy + dy), gridPaint);
    }
    
    // Depth rings
    for (int i = 1; i <= 6; i++) {
        final r = (size.width * 0.8) * math.pow(i/6.0, 1.5);
        canvas.drawOval(Rect.fromCenter(center: vp, width: r*2, height: r*2), 
           Paint()..color = const Color(0xFF1A3A6A).withValues(alpha: 0.2)..style=PaintingStyle.stroke..strokeWidth=1);
    }

    // Targets
    for (final tgt in targets) {
      // Perspective projection
      // z=0 -> far (small, near vp)
      // z=1 -> interaction plane (full size)
      final scale = math.pow(tgt.z, 0.8).toDouble(); 
      if (scale < 0.05) continue; // Too far to see

      // Project X and Y relative to vanishing point based on depth scale
      final px = cx + (tgt.x * size.width * 0.45 * scale);
      final py = cy + (tgt.y * size.height * 0.45 * scale);
      
      final radius = 40.0 * scale;
      
      // Color shifts as it gets closer. 
      // Bright blue -> Bright Orange right at hit plane -> Red if missed
      Color c = const Color(0xFF4FC3F7); // Default incoming
      if (tgt.z > 0.85 && tgt.z < 1.1) {
          c = const Color(0xFFFFAB40); // Hit zone
      } else if (tgt.z >= 1.1) {
          c = const Color(0xFFFF5252); // Missed zone
      }

      final alpha = (scale * 255).clamp(0, 255).toInt();
      final paint = Paint()..color = c.withAlpha(alpha);
      
      canvas.drawCircle(Offset(px, py), radius, paint);
      
      // Core highlight
      canvas.drawCircle(Offset(px - radius*0.3, py - radius*0.3), radius*0.3, 
          Paint()..color = Colors.white.withAlpha((alpha*0.8).toInt()));
    }
  }

  @override
  bool shouldRepaint(_VrEnvironmentPainter old) => true; // Needs repaint every frame
}
