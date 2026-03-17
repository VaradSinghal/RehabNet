/// VR Hand Interaction Screen — Enhanced
///
/// Renders a pseudo-3D perspective environment ("tunnel").
/// Virtual targets approach the viewer. The user drags a hand cursor
/// to intercept them.
///
/// Features:
///   - Difficulty selector (Easy / Medium / Hard)
///   - Walking Path mode (targets in a lane)
///   - Session timer with final score summary
///   - Audio metronome beep for rhythmic cueing

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class VrHandScreen extends StatefulWidget {
  const VrHandScreen({super.key});
  @override
  State<VrHandScreen> createState() => _VrHandScreenState();
}

enum VrDifficulty { easy, medium, hard }

class _VrHandScreenState extends State<VrHandScreen>
    with SingleTickerProviderStateMixin {
  // ── Config ──────────────────────────────────────────────────────────
  VrDifficulty _difficulty = VrDifficulty.medium;
  bool _walkingPathMode = false;

  double get _approachSpeed {
    switch (_difficulty) {
      case VrDifficulty.easy:   return 0.008;
      case VrDifficulty.medium: return 0.015;
      case VrDifficulty.hard:   return 0.025;
    }
  }

  double get _hitRadius {
    switch (_difficulty) {
      case VrDifficulty.easy:   return 0.25;
      case VrDifficulty.medium: return 0.15;
      case VrDifficulty.hard:   return 0.10;
    }
  }

  double get _spawnRate {
    switch (_difficulty) {
      case VrDifficulty.easy:   return 0.15;
      case VrDifficulty.medium: return 0.25;
      case VrDifficulty.hard:   return 0.40;
    }
  }

  // ── Game state ──────────────────────────────────────────────────────
  late Timer _timer;
  bool _running = false;
  bool _showSummary = false;

  double _handX = 0.5;
  double _handY = 0.5;

  int _score = 0;
  int _missed = 0;
  int _sessionSeconds = 60; // Countdown
  Timer? _countdownTimer;

  final List<_Target3D> _targets = [];
  final math.Random _rng = math.Random();

  // Audio
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _metronomeEnabled = false;
  Timer? _metronomeTimer;

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    _score = 0;
    _missed = 0;
    _sessionSeconds = 60;
    _targets.clear();
    _showSummary = false;

    setState(() { _running = true; });

    _timer = Timer.periodic(const Duration(milliseconds: 32), _gameLoop);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() { _sessionSeconds--; });
      if (_sessionSeconds <= 0) {
        _endGame();
      }
    });

    if (_metronomeEnabled) _startMetronome();
  }

  void _endGame() {
    _running = false;
    _timer.cancel();
    _countdownTimer?.cancel();
    _metronomeTimer?.cancel();
    setState(() { _showSummary = true; });
  }

  void _startMetronome() {
    _metronomeTimer?.cancel();
    _metronomeTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!_running) return;
      try {
        _beepPlayer.play(AssetSource('audio/beep.wav'), volume: 0.3);
      } catch (_) {}
    });
  }

  void _gameLoop(Timer t) {
    if (!mounted || !_running) return;

    setState(() {
      // Spawn logic
      final shouldSpawn = _targets.isEmpty ||
          (_targets.last.z > 0.4 && _rng.nextDouble() < _spawnRate);

      if (shouldSpawn) {
        if (_walkingPathMode) {
          // Walking path: targets come in lanes (-0.5, 0, 0.5)
          final lanes = [-0.6, 0.0, 0.6];
          final laneIdx = _rng.nextInt(3);
          _targets.add(_Target3D(
            x: lanes[laneIdx],
            y: 0.3, // slightly below center for a "step" feel
            z: 0.0,
          ));
        } else {
          _targets.add(_Target3D(
            x: (_rng.nextDouble() * 2) - 1.0,
            y: (_rng.nextDouble() * 2) - 1.0,
            z: 0.0,
          ));
        }
      }

      // Move targets
      for (int i = _targets.length - 1; i >= 0; i--) {
        final tgt = _targets[i];
        tgt.z += _approachSpeed;

        // Hit check
        if (tgt.z >= 0.85 && tgt.z <= 1.1) {
          final hx = (_handX * 2) - 1.0;
          final hy = (_handY * 2) - 1.0;
          final dx = tgt.x - hx;
          final dy = tgt.y - hy;
          final distSq = dx * dx + dy * dy;

          if (distSq < _hitRadius) {
            _score++;
            _targets.removeAt(i);
            continue;
          }
        }

        // Missed
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
    _countdownTimer?.cancel();
    _metronomeTimer?.cancel();
    _beepPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showSummary) return _buildSummary(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onPanDown: _onPanDown,
        onPanUpdate: _onPanUpdate,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 3D Environment
            CustomPaint(
              painter: _VrEnvironmentPainter(
                  targets: _targets, walkingPath: _walkingPathMode),
            ),

            // Player hand cursor
            Positioned(
              left: MediaQuery.of(context).size.width * _handX - 35,
              top: MediaQuery.of(context).size.height * _handY - 35,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  border:
                      Border.all(color: const Color(0xFF00C896), width: 3),
                  boxShadow: [
                    BoxShadow(
                        color:
                            const Color(0xFF00C896).withValues(alpha: 0.5),
                        blurRadius: 15)
                  ],
                ),
                child: const Icon(Icons.pan_tool,
                    color: Color(0xFF00C896), size: 30),
              ),
            ),

            // Top HUD
            _buildHUD(context),

            // Bottom controls
            _buildBottomBar(),

            // Timer
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _sessionSeconds <= 10
                        ? const Color(0xFFFF5252).withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _sessionSeconds <= 10
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF4FC3F7).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${_sessionSeconds}s',
                    style: TextStyle(
                      color: _sessionSeconds <= 10
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF4FC3F7),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHUD(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 36,
          left: 20,
          right: 20,
          bottom: 14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.transparent
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon:
                  const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Column(
              children: [
                Text(
                    _walkingPathMode
                        ? 'WALKING PATH'
                        : 'VR HAND INTERACTION',
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontFamily: 'Inter',
                        letterSpacing: 1.5)),
                Text('Score: $_score',
                    style: const TextStyle(
                        color: Color(0xFF4FC3F7),
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Missed',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'Inter')),
                Text('$_missed',
                    style: const TextStyle(
                        color: Color(0xFFFF5252),
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 12,
          top: 12,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Difficulty
            _ControlChip(
              icon: Icons.speed_rounded,
              label: _difficulty.name.toUpperCase(),
              color: const Color(0xFFFFAB40),
              onTap: () {
                setState(() {
                  final values = VrDifficulty.values;
                  _difficulty =
                      values[(_difficulty.index + 1) % values.length];
                });
              },
            ),
            // Mode toggle
            _ControlChip(
              icon: _walkingPathMode
                  ? Icons.directions_walk_rounded
                  : Icons.back_hand_rounded,
              label: _walkingPathMode ? 'WALK' : 'CATCH',
              color: const Color(0xFF4FC3F7),
              onTap: () {
                setState(() {
                  _walkingPathMode = !_walkingPathMode;
                });
              },
            ),
            // Metronome toggle
            _ControlChip(
              icon: Icons.music_note_rounded,
              label: _metronomeEnabled ? 'ON' : 'OFF',
              color: _metronomeEnabled
                  ? const Color(0xFF00C896)
                  : const Color(0xFF4A5568),
              onTap: () {
                setState(() {
                  _metronomeEnabled = !_metronomeEnabled;
                  if (_metronomeEnabled && _running) {
                    _startMetronome();
                  } else {
                    _metronomeTimer?.cancel();
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final total = _score + _missed;
    final accuracy = total == 0 ? 0.0 : (_score / total) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: Color(0xFFFFAB40), size: 72),
              const SizedBox(height: 24),
              const Text('Session Complete!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter')),
              const SizedBox(height: 32),

              // Stats grid
              Row(
                children: [
                  Expanded(
                      child: _SummaryCard(
                          'Score', '$_score', const Color(0xFF00C896))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _SummaryCard(
                          'Missed', '$_missed', const Color(0xFFFF5252))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _SummaryCard('Accuracy',
                          '${accuracy.toStringAsFixed(0)}%',
                          const Color(0xFF4FC3F7))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _SummaryCard('Difficulty',
                          _difficulty.name.toUpperCase(),
                          const Color(0xFFFFAB40))),
                ],
              ),
              const SizedBox(height: 40),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Exit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF1E2840)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _startGame();
                      },
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Play Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter')),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8892A4),
                  fontSize: 12,
                  fontFamily: 'Inter')),
        ],
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter')),
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

// ── Environment CustomPainter ─────────────────────────────────────────────────
class _VrEnvironmentPainter extends CustomPainter {
  final List<_Target3D> targets;
  final bool walkingPath;
  _VrEnvironmentPainter({required this.targets, required this.walkingPath});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060D1F), Color(0xFF040A1A), Color(0xFF02050D)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final vp = Offset(cx, cy);
    final gridPaint = Paint()
      ..color = const Color(0xFF1A3A6A).withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Perspective lines
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2;
      final dx = math.cos(angle) * size.width;
      final dy = math.sin(angle) * size.height;
      canvas.drawLine(vp, Offset(cx + dx, cy + dy), gridPaint);
    }

    // Depth rings
    for (int i = 1; i <= 6; i++) {
      final r = (size.width * 0.8) * math.pow(i / 6.0, 1.5);
      canvas.drawOval(
        Rect.fromCenter(center: vp, width: r * 2, height: r * 2),
        Paint()
          ..color = const Color(0xFF1A3A6A).withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Walking path lanes
    if (walkingPath) {
      for (final laneX in [-0.6, 0.0, 0.6]) {
        final lanePaint = Paint()
          ..color = const Color(0xFF1A3A6A).withValues(alpha: 0.4)
          ..strokeWidth = 2;
        final topP = Offset(cx + laneX * size.width * 0.05, cy);
        final botP = Offset(
            cx + laneX * size.width * 0.45, size.height);
        canvas.drawLine(topP, botP, lanePaint);
      }
    }

    // Targets
    for (final tgt in targets) {
      final scale = math.pow(tgt.z, 0.8).toDouble();
      if (scale < 0.05) continue;

      final px = cx + (tgt.x * size.width * 0.45 * scale);
      final py = cy + (tgt.y * size.height * 0.45 * scale);
      final radius = (walkingPath ? 30.0 : 40.0) * scale;

      Color c = const Color(0xFF4FC3F7);
      if (tgt.z > 0.85 && tgt.z < 1.1) {
        c = const Color(0xFFFFAB40);
      } else if (tgt.z >= 1.1) {
        c = const Color(0xFFFF5252);
      }

      final alpha = (scale * 255).clamp(0, 255).toInt();
      canvas.drawCircle(Offset(px, py), radius, Paint()..color = c.withAlpha(alpha));
      canvas.drawCircle(
        Offset(px - radius * 0.3, py - radius * 0.3),
        radius * 0.3,
        Paint()..color = Colors.white.withAlpha((alpha * 0.8).toInt()),
      );
    }
  }

  @override
  bool shouldRepaint(_VrEnvironmentPainter old) => true;
}
