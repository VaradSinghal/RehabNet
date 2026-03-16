/// AR Hand Agility Screen
/// Shows live camera feed with:
///   - ML Kit skeleton overlay (CustomPainter) focused on arms/hands.
///   - Randomized AR targets that appear at different arm's-reach positions.
///   - Patient must reach out to "touch" the target with their wrist.
///   - Tracks hits, accuracy, and reaction speed.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/feedback_banner.dart';

class ArExerciseScreen extends StatefulWidget {
  const ArExerciseScreen({super.key});
  @override
  State<ArExerciseScreen> createState() => _ArExerciseScreenState();
}

class _ArExerciseScreenState extends State<ArExerciseScreen>
    with TickerProviderStateMixin {
  // Camera
  CameraController? _camCtrl;
  List<CameraDescription> _cameras = [];
  bool _camReady = false;

  // ML Kit
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  bool _detecting = false;
  Pose? _pose;

  // Game state
  final math.Random _rng = math.Random();
  int _hits = 0;
  int _misses = 0;
  String _feedback = 'Reach for the target!';
  bool _feedbackPositive = true;

  // AR Target
  double _targetNX = 0.5; // Normalized x (0..1)
  double _targetNY = 0.3; // Normalized y (0..1)
  static const double _hitRadius = 0.12; // Distance threshold to register hit
  static const int _targetTimeoutMs = 3000; // Time to hit before miss

  DateTime _targetSpawnedAt = DateTime.now();
  Timer? _gameTimer;

  // Pulsing animation for AR target
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 30, end: 45).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _initCamera();
    _spawnTarget();
    _startGameLoop();
  }

  void _spawnTarget() {
    setState(() {
      // Keep targets in the upper/middle area (arm's reach)
      _targetNX = 0.2 + _rng.nextDouble() * 0.6; // 0.2 - 0.8
      _targetNY = 0.2 + _rng.nextDouble() * 0.5; // 0.2 - 0.7
      _targetSpawnedAt = DateTime.now();
    });
  }

  void _startGameLoop() {
    _gameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final elapsed = DateTime.now().difference(_targetSpawnedAt).inMilliseconds;
      if (elapsed > _targetTimeoutMs) {
        // Target missed (too slow)
        setState(() {
          _misses++;
          _feedback = 'Too slow, try the next one!';
          _feedbackPositive = false;
        });
        _spawnTarget();
      }
    });
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    final cam = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _camCtrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
    await _camCtrl!.initialize();
    _camCtrl!.startImageStream(_onCameraFrame);

    if (mounted) setState(() => _camReady = true);
  }

  void _onCameraFrame(CameraImage img) async {
    if (_detecting) return;
    _detecting = true;

    try {
      final inputImage = _buildInputImage(img);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isEmpty) {
        _detecting = false;
        return;
      }

      final pose = poses.first;
      _analysePose(pose);

      if (mounted) setState(() => _pose = pose);
    } catch (_) {}

    _detecting = false;
  }

  InputImage? _buildInputImage(CameraImage img) {
    if (_camCtrl == null) return null;
    final cam = _camCtrl!.description;
    final rotation = InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(img.format.raw);
    if (format == null || img.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: img.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: img.planes.first.bytesPerRow,
      ),
    );
  }

  void _analysePose(Pose pose) {
    final wristL = pose.landmarks[PoseLandmarkType.leftWrist];
    final wristR = pose.landmarks[PoseLandmarkType.rightWrist];

    // Check distance of both wrists to the target
    final distL = wristL != null ? _sqDist(wristL.x, wristL.y, _targetNX, _targetNY) : double.infinity;
    final distR = wristR != null ? _sqDist(wristR.x, wristR.y, _targetNX, _targetNY) : double.infinity;

    final thresholdSq = _hitRadius * _hitRadius;

    if (distL < thresholdSq || distR < thresholdSq) {
      // Hit!
      final reactionTimeMs = DateTime.now().difference(_targetSpawnedAt).inMilliseconds;
      setState(() {
        _hits++;
        _feedback = 'Hit! Reaction: ${(reactionTimeMs / 1000).toStringAsFixed(1)}s';
        _feedbackPositive = true;
      });
      _spawnTarget();
    }
  }

  double _sqDist(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return dx * dx + dy * dy;
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _poseDetector.close();
    _camCtrl?.stopImageStream();
    _camCtrl?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _camReady && _camCtrl != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_camCtrl!),

                // Skeleton overlay
                CustomPaint(
                  painter: _PosePainter(pose: _pose, previewSize: _camCtrl!.value.previewSize!),
                ),

                // AR target
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => _buildARTarget(context),
                ),

                // HUD
                _buildHUD(),

                // Feedback
                Positioned(
                  bottom: 40,
                  left: 16,
                  right: 16,
                  child: FeedbackBanner(
                    message: _feedback,
                    isPositive: _feedbackPositive,
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator(color: Color(0xFF00C896))),
    );
  }

  Widget _buildARTarget(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // To calculate time remaining for the target wrapper
    final elapsed = DateTime.now().difference(_targetSpawnedAt).inMilliseconds;
    final remainingPct = 1.0 - (elapsed / _targetTimeoutMs).clamp(0.0, 1.0);
    
    final radius = _pulseAnim.value;
    final glowRad = radius * 1.5;

    return Positioned(
      left: size.width * _targetNX - radius,
      top: size.height * _targetNY - radius,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Time remaining ring
          SizedBox(
            width: radius * 2.3,
            height: radius * 2.3,
            child: CircularProgressIndicator(
              value: remainingPct,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(
                remainingPct > 0.3 ? const Color(0xFF00C896) : const Color(0xFFFF5252)
              ),
              backgroundColor: Colors.transparent,
            ),
          ),
          
          // Outer glow
          Container(
            width: glowRad * 2,
            height: glowRad * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00C896).withValues(alpha: 0.15),
              boxShadow: [
                BoxShadow(color: const Color(0xFF00C896).withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 4),
              ],
            ),
          ),

          // Inner core
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00C896).withValues(alpha: 0.3),
              border: Border.all(color: const Color(0xFF00C896), width: 3),
            ),
            child: const Icon(Icons.back_hand, color: Color(0xFF00C896), size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildHUD() {
    final total = _hits + _misses;
    final acc = total == 0 ? 0.0 : (_hits / total) * 100;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16, bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            BackButton(color: Colors.white, onPressed: () => Navigator.pop(context)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('HAND AGILITY',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Inter', letterSpacing: 1.5)),
                Text('$_hits Hits',
                    style: const TextStyle(
                        color: Color(0xFF00C896), fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Accuracy',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Inter')),
                Text('${acc.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Color(0xFF4FC3F7), fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Skeleton CustomPainter â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PosePainter extends CustomPainter {
  final Pose? pose;
  final Size previewSize;

  _PosePainter({required this.pose, required this.previewSize});

  static const _jointColor = Color(0xFF00C896);
  static const _boneColor  = Color(0xFF4FC3F7);

  static const _connections = [
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow,     PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow,    PoseLandmarkType.rightWrist],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null) return;

    final bonePaint = Paint()..color = _boneColor.withValues(alpha: 0.8)..strokeWidth = 3.0..style = PaintingStyle.stroke;
    final jointPaint = Paint()..color = _jointColor..style = PaintingStyle.fill;
    final jointBorder = Paint()..color = Colors.white.withValues(alpha: 0.6)..strokeWidth = 2.0..style = PaintingStyle.stroke;

    final sx = size.width;
    final sy = size.height;

    // Draw arm bones only
    for (final conn in _connections) {
      final a = pose!.landmarks[conn[0]];
      final b = pose!.landmarks[conn[1]];
      if (a != null && b != null && a.likelihood > 0.5 && b.likelihood > 0.5) {
        canvas.drawLine(
          Offset(a.x * sx, a.y * sy),
          Offset(b.x * sx, b.y * sy),
          bonePaint,
        );
      }
    }

    // Draw arm joints only
    final relevantJoints = [
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist
    ];

    for (final type in relevantJoints) {
      final lm = pose!.landmarks[type];
      if (lm != null && lm.likelihood > 0.5) {
        final p = Offset(lm.x * sx, lm.y * sy);
        
        // Emphasize wrists
        final isWrist = type == PoseLandmarkType.leftWrist || type == PoseLandmarkType.rightWrist;
        final r = isWrist ? 10.0 : 6.0;
        
        if (isWrist) {
           canvas.drawCircle(p, r + 4, Paint()..color = Colors.white.withValues(alpha: 0.3)..style = PaintingStyle.fill);
        }
        
        canvas.drawCircle(p, r, jointPaint);
        canvas.drawCircle(p, r, jointBorder);
      }
    }
  }

  @override
  bool shouldRepaint(_PosePainter old) => old.pose != pose;
}
