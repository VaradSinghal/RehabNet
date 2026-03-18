/// AR Exercise Screen — Camera-based hand tracking rehabilitation.
///
/// 1. Target Touch  — move your HAND to reach random AR targets
/// 2. Guided Path   — trace a curved path with your wrist
/// 3. Arm Raise     — counts full arm raises (wrist above shoulder)
///
/// ML Kit Pose Detection tracks wrists in real time.
/// Bounding boxes rendered around detected hands.
/// Coordinate system: properly handles front camera mirroring + sensor rotation.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';
import '../widgets/feedback_banner.dart';
import '../widgets/exercise_selector.dart';
import '../services/session_service.dart';
import '../services/api_service.dart';
import '../services/api_websocket_service.dart';

class ArExerciseScreen extends StatefulWidget {
  const ArExerciseScreen({super.key});
  @override
  State<ArExerciseScreen> createState() => _ArExerciseScreenState();
}

class _ArExerciseScreenState extends State<ArExerciseScreen>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _camReady = false;
  bool _isFrontCamera = true;

  // ── ML Kit ──────────────────────────────────────────────────────────
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  bool _detecting = false;
  Pose? _pose;
  Size _imageSize = const Size(480, 640);
  InputImageRotation _imageRotation = InputImageRotation.rotation0deg;

  // Tracked hand screen positions (actual pixel coordinates on screen)
  Offset? _leftHandScreen;
  Offset? _rightHandScreen;

  // ── Exercise state ──────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _showInstructions = true;
  String _activeExercise = 'target_touch';
  final math.Random _rng = math.Random();
  int _hits = 0;
  int _misses = 0;
  String _feedback = 'Stand so the camera sees your hands';
  bool _feedbackPositive = true;
  int _frameCount = 0;
  bool _poseDetected = false;

  // ── Target Touch ────────────────────────────────────────────────────
  double _targetNX = 0.5;
  double _targetNY = 0.3;
  static const double _hitRadiusPx = 70.0;
  static const int _targetTimeoutMs = 4500;
  DateTime _targetSpawnedAt = DateTime.now();
  Timer? _timeoutTimer;

  // ── Guided Path ─────────────────────────────────────────────────────
  List<Offset> _pathPoints = [];
  int _pathProgress = 0;
  static const double _pathReachPx = 50.0;

  // ── Arm Raise ───────────────────────────────────────────────────────
  bool _armWasDown = true;
  int _armRaiseReps = 0;

  // ── Animation ───────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── API ─────────────────────────────────────────────────────────────
  late final ApiService _api;

  @override
  void initState() {
    super.initState();
    _api = ApiService(baseUrl: ApiWebSocketService().baseUrl);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 34, end: 52)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _initCamera();
    _generatePath();
    _spawnTarget();
    _startTimeoutLoop();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CAMERA + ML KIT
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _isFrontCamera = cam.lensDirection == CameraLensDirection.front;

      _camCtrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _camCtrl!.initialize();
      await _camCtrl!.startImageStream(_onCameraFrame);
      if (mounted) setState(() => _camReady = true);
    } catch (e) {
      debugPrint('[AR] Camera error: $e');
    }
  }

  void _onCameraFrame(CameraImage img) async {
    if (_detecting || !mounted) return;
    _detecting = true;
    _frameCount++;

    if (_frameCount % 2 != 0) {
      _detecting = false;
      return;
    }

    try {
      final inputImage = _buildInputImage(img);
      if (inputImage == null) {
        _detecting = false;
        return;
      }

      _imageSize = Size(img.width.toDouble(), img.height.toDouble());
      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isNotEmpty && mounted) {
        final pose = poses.first;
        final screenSize = MediaQuery.of(context).size;

        // Convert ML Kit pixel coords → screen pixel coords
        final lw = pose.landmarks[PoseLandmarkType.leftWrist];
        final rw = pose.landmarks[PoseLandmarkType.rightWrist];

        setState(() {
          _pose = pose;
          _poseDetected = true;
          _leftHandScreen = (lw != null && lw.likelihood > 0.5)
              ? _translateToScreen(lw, screenSize)
              : null;
          _rightHandScreen = (rw != null && rw.likelihood > 0.5)
              ? _translateToScreen(rw, screenSize)
              : null;
        });

        _processExercise(pose, screenSize);

        if (_frameCount % 15 == 0) _sendToBackend(pose);
      } else if (mounted) {
        setState(() {
          _poseDetected = false;
          _leftHandScreen = null;
          _rightHandScreen = null;
        });
      }
    } catch (e) {
      debugPrint('[AR] ML Kit: $e');
    }

    _detecting = false;
  }

  InputImage? _buildInputImage(CameraImage img) {
    if (_camCtrl == null) return null;
    final cam = _camCtrl!.description;
    final rotation =
        InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    if (rotation == null) return null;
    _imageRotation = rotation;

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

  /// Translates an ML Kit landmark (in image pixel coordinates)
  /// to Flutter screen coordinates, accounting for:
  ///   - Sensor rotation (90°, 270°, etc.)
  ///   - Front camera horizontal mirroring
  ///   - Aspect ratio scaling to fill the screen
  Offset _translateToScreen(PoseLandmark lm, Size screenSize) {
    double x = lm.x;
    double y = lm.y;

    // The image from the camera sensor is typically in landscape orientation.
    // ML Kit returns coordinates in the ROTATED image space.
    // We need to figure out the "absolute" image dimensions after rotation.
    double absWidth, absHeight;
    switch (_imageRotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        absWidth = _imageSize.height;
        absHeight = _imageSize.width;
        break;
      default:
        absWidth = _imageSize.width;
        absHeight = _imageSize.height;
    }

    // Normalize to 0..1
    double nx = x / absWidth;
    double ny = y / absHeight;

    // Front camera: mirror horizontally
    if (_isFrontCamera) {
      nx = 1.0 - nx;
    }

    // Clamp
    nx = nx.clamp(0.0, 1.0);
    ny = ny.clamp(0.0, 1.0);

    return Offset(nx * screenSize.width, ny * screenSize.height);
  }

  /// Same but returns normalized 0..1
  Offset _translateToNormalized(PoseLandmark lm) {
    double x = lm.x;
    double y = lm.y;

    double absWidth, absHeight;
    switch (_imageRotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        absWidth = _imageSize.height;
        absHeight = _imageSize.width;
        break;
      default:
        absWidth = _imageSize.width;
        absHeight = _imageSize.height;
    }

    double nx = x / absWidth;
    double ny = y / absHeight;
    if (_isFrontCamera) nx = 1.0 - nx;

    return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
  }

  // ═══════════════════════════════════════════════════════════════════
  //  EXERCISE LOGIC
  // ═══════════════════════════════════════════════════════════════════

  void _processExercise(Pose pose, Size screenSize) {
    switch (_activeExercise) {
      case 'target_touch':
        _processTargetTouch(screenSize);
        break;
      case 'guided_path':
        _processGuidedPath(screenSize);
        break;
      case 'arm_raise':
        _processArmRaise(pose);
        break;
    }
  }

  // ── Target Touch ────────────────────────────────────────────────────
  void _spawnTarget() {
    _targetNX = 0.15 + _rng.nextDouble() * 0.70;
    _targetNY = 0.22 + _rng.nextDouble() * 0.48;
    _targetSpawnedAt = DateTime.now();
  }

  void _startTimeoutLoop() {
    _timeoutTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_activeExercise != 'target_touch' || !mounted) return;
      final elapsed =
          DateTime.now().difference(_targetSpawnedAt).inMilliseconds;
      if (elapsed > _targetTimeoutMs) {
        setState(() {
          _misses++;
          _feedback = 'Missed! Move your hand faster';
          _feedbackPositive = false;
        });
        _spawnTarget();
      }
      if (mounted) setState(() {});
    });
  }

  void _processTargetTouch(Size screenSize) {
    final targetPx = Offset(
      screenSize.width * _targetNX,
      screenSize.height * _targetNY,
    );

    for (final hand in [_leftHandScreen, _rightHandScreen]) {
      if (hand == null) continue;
      final dist = (hand - targetPx).distance;
      if (dist < _hitRadiusPx) {
        final ms =
            DateTime.now().difference(_targetSpawnedAt).inMilliseconds;
        setState(() {
          _hits++;
          _feedback =
              'Hit! ${(ms / 1000).toStringAsFixed(1)}s reaction';
          _feedbackPositive = true;
        });
        context.read<SessionService>().addRep(accuracy: 100.0);
        _spawnTarget();
        return;
      }
    }
  }

  // ── Guided Path ─────────────────────────────────────────────────────
  void _generatePath() {
    _pathPoints = [];
    _pathProgress = 0;
    const n = 7;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = 0.15 + 0.70 * t;
      final y = 0.40 + 0.14 * math.sin(t * math.pi * 2);
      _pathPoints.add(Offset(x, y));
    }
  }

  void _processGuidedPath(Size screenSize) {
    if (_pathProgress >= _pathPoints.length) return;

    final target = _pathPoints[_pathProgress];
    final targetPx = Offset(
      target.dx * screenSize.width,
      target.dy * screenSize.height,
    );

    for (final hand in [_rightHandScreen, _leftHandScreen]) {
      if (hand == null) continue;
      if ((hand - targetPx).distance < _pathReachPx) {
        setState(() {
          _pathProgress++;
          if (_pathProgress >= _pathPoints.length) {
            _feedback = 'Path complete! Great job!';
            _feedbackPositive = true;
            _hits++;
            context.read<SessionService>().addRep(accuracy: 95.0);
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (mounted) {
                _generatePath();
                setState(() => _feedback = 'New path! Move your hand');
              }
            });
          } else {
            _feedback = 'Point $_pathProgress/${_pathPoints.length}';
            _feedbackPositive = true;
          }
        });
        return;
      }
    }
  }

  // ── Arm Raise ───────────────────────────────────────────────────────
  void _processArmRaise(Pose pose) {
    final wristR = pose.landmarks[PoseLandmarkType.rightWrist];
    final shoulderR = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (wristR == null || shoulderR == null) return;
    if (wristR.likelihood < 0.5 || shoulderR.likelihood < 0.5) return;

    // Use normalized coordinates for comparison
    final wNorm = _translateToNormalized(wristR);
    final sNorm = _translateToNormalized(shoulderR);
    // In screen space: smaller Y = higher. So shoulder.y - wrist.y > 0 = raised.
    final heightRatio = sNorm.dy - wNorm.dy;

    if (heightRatio > 0.08 && _armWasDown) {
      _armWasDown = false;
      setState(() {
        _armRaiseReps++;
        _feedback = 'Rep $_armRaiseReps — Excellent!';
        _feedbackPositive = true;
      });
      context.read<SessionService>().addRep(accuracy: 95.0);
    } else if (heightRatio < 0.02) {
      if (!_armWasDown) {
        setState(() {
          _feedback = 'Good. Raise again!';
          _feedbackPositive = true;
        });
      }
      _armWasDown = true;
    } else if (heightRatio > 0 && heightRatio < 0.08 && _armWasDown) {
      setState(() {
        _feedback = 'Raise higher!';
        _feedbackPositive = false;
      });
    }
  }

  // ── Backend POST ────────────────────────────────────────────────────
  void _sendToBackend(Pose pose) async {
    final List<Map<String, dynamic>> lmJson = [];
    pose.landmarks.forEach((type, lm) {
      final n = _translateToNormalized(lm);
      lmJson.add({
        'x': n.dx, 'y': n.dy, 'z': lm.z,
        'likelihood': lm.likelihood,
        'type': type.toString().split('.').last,
      });
    });
    try {
      final result = await _api.sendPoseData(
          userId: 1, landmarks: lmJson, exercise: _activeExercise);

      // Use the AI classification & feedback from the backend
      if (result != null && mounted) {
        final classification = result['classification'] as String? ?? '';
        final aiFeedback = result['feedback'] as String? ?? '';
        final aiAccuracy = (result['accuracy_pct'] as num?)?.toDouble() ?? 0.0;

        if (classification.isNotEmpty && aiFeedback.isNotEmpty) {
          setState(() {
            _feedback = '🤖 $aiFeedback';
            _feedbackPositive = classification == 'Correct';
          });
          // Update session accuracy from AI when classification is positive
          if (classification == 'Correct' && aiAccuracy > 0) {
            context.read<SessionService>().updateMetrics(newAccuracy: aiAccuracy);
          }
        }
      }
    } catch (_) {}
  }

  void _switchExercise(ExerciseInfo ex) {
    setState(() {
      _activeExercise = ex.id;
      _hits = 0;
      _misses = 0;
      _pathProgress = 0;
      _armRaiseReps = 0;
      _armWasDown = true;
      _feedbackPositive = true;
      switch (ex.id) {
        case 'target_touch':
          _feedback = 'Move your HAND to touch the green target shown on screen.';
          break;
        case 'guided_path':
          _feedback = 'Follow the curved path carefully with your wrist.';
          break;
        case 'arm_raise':
          _feedback = 'Stand back. Raise your arm high above your shoulder, then lower it.';
          break;
      }
    });
    if (ex.id == 'target_touch') _spawnTarget();
    if (ex.id == 'guided_path') _generatePath();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _poseDetector.close();
    _camCtrl?.stopImageStream();
    _camCtrl?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    final safePad = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera feed ──────────────────────────────────────────
          if (_camReady && _camCtrl != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _camCtrl!.value.previewSize!.height,
                  height: _camCtrl!.value.previewSize!.width,
                  child: CameraPreview(_camCtrl!),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0D1221), Color(0xFF060D1F)],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: Color(0xFF00C896), strokeWidth: 3),
                    SizedBox(height: 16),
                    Text('Starting Camera...',
                        style: TextStyle(
                            color: Color(0xFF8892A4),
                            fontFamily: 'Inter',
                            fontSize: 14)),
                  ],
                ),
              ),
            ),

          // ── Dark vignette overlay for readability ────────────────
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
                ),
              ),
            ),
          ),

          // ── Skeleton overlay ─────────────────────────────────────
          if (_pose != null)
            CustomPaint(
              painter: _SkeletonPainter(
                pose: _pose!,
                imageSize: _imageSize,
                screenSize: sz,
                imageRotation: _imageRotation,
                isFrontCamera: _isFrontCamera,
              ),
            ),

          // ── Hand bounding boxes ──────────────────────────────────
          if (_leftHandScreen != null)
            _HandBox(
              position: _leftHandScreen!,
              label: 'LEFT',
              isNearTarget: _isHandNearTarget(_leftHandScreen!),
            ),
          if (_rightHandScreen != null)
            _HandBox(
              position: _rightHandScreen!,
              label: 'RIGHT',
              isNearTarget: _isHandNearTarget(_rightHandScreen!),
            ),

          // ── Exercise overlays ───────────────────────────────────
          if (_activeExercise == 'target_touch')
            _buildTarget(sz),

          if (_activeExercise == 'guided_path')
            CustomPaint(
              painter: _PathPainter(
                points: _pathPoints,
                progress: _pathProgress,
                screenSize: sz,
              ),
            ),

          if (_activeExercise == 'arm_raise')
            _buildArmRaiseHUD(),

          // ── Top gradient + Back + Stats ──────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(
                  top: safePad.top + 6, left: 12, right: 12, bottom: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
              child: Row(
                children: [
                  // Back
                  _GlassButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // Stats
                  _StatPill(
                    icon: Icons.ads_click_rounded,
                    value: '$_hits',
                    label: 'Hits',
                    color: const Color(0xFF00C896),
                  ),
                  const SizedBox(width: 8),
                  _StatPill(
                    icon: Icons.close_rounded,
                    value: '$_misses',
                    label: 'Miss',
                    color: const Color(0xFFFF5252),
                  ),
                  const SizedBox(width: 8),
                  _StatPill(
                    icon: Icons.percent_rounded,
                    value: _accuracy,
                    label: 'Acc',
                    color: const Color(0xFF4FC3F7),
                  ),
                ],
              ),
            ),
          ),

          // ── Exercise Selector ───────────────────────────────────
          Positioned(
            top: safePad.top + 56,
            left: 0, right: 0,
            child: ExerciseSelector(
              selected: _activeExercise,
              onSelected: _switchExercise,
            ),
          ),

          // ── Tracking chip ───────────────────────────────────────
          Positioned(
            bottom: 80, right: 12,
            child: _TrackingChip(detected: _poseDetected),
          ),

          // ── Instruction Overlay (Elderly Friendly) ────────────────────────
          if (_showInstructions)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131929),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF00C896).withValues(alpha: 0.5),
                            width: 2),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.camera_front_rounded,
                              size: 56, color: Color(0xFF00C896)),
                          const SizedBox(height: 16),
                          const Text(
                            'How to Play',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Inter'),
                          ),
                          const SizedBox(height: 16),
                          const _InstructionRow(
                              icon: Icons.back_hand_rounded,
                              text:
                                  'Prop your phone up. Stand back so camera sees your shoulders & hands.'),
                          const SizedBox(height: 12),
                          const _InstructionRow(
                              icon: Icons.center_focus_strong_rounded,
                              text:
                                  'The app tracks your REAL hand movement. Do not touch the screen.'),
                          const SizedBox(height: 12),
                          const _InstructionRow(
                              icon: Icons.check_circle_rounded,
                              text:
                                  'Move your hands in the air to reach the targets shown on screen.'),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _showInstructions = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('I Understand, Start!',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Inter')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Feedback ────────────────────────────────────────────
          if (!_showInstructions)
            Positioned(
              bottom: 24, left: 16, right: 16,
              child: FeedbackBanner(
                message: _feedback,
                isPositive: _feedbackPositive,
              ),
            ),
        ],
      ),
    );
  }

  String get _accuracy {
    final total = _hits + _misses;
    return total == 0 ? '—' : '${((_hits / total) * 100).toStringAsFixed(0)}%';
  }

  bool _isHandNearTarget(Offset handPx) {
    final sz = MediaQuery.of(context).size;
    if (_activeExercise == 'target_touch') {
      final t = Offset(sz.width * _targetNX, sz.height * _targetNY);
      return (handPx - t).distance < _hitRadiusPx * 1.8;
    }
    if (_activeExercise == 'guided_path' && _pathProgress < _pathPoints.length) {
      final p = _pathPoints[_pathProgress];
      final t = Offset(sz.width * p.dx, sz.height * p.dy);
      return (handPx - t).distance < _pathReachPx * 1.8;
    }
    return false;
  }

  // ── Target widget ───────────────────────────────────────────────────
  Widget _buildTarget(Size sz) {
    final elapsed = DateTime.now().difference(_targetSpawnedAt).inMilliseconds;
    final pct = 1.0 - (elapsed / _targetTimeoutMs).clamp(0.0, 1.0);
    final r = _pulseAnim.value;

    return Positioned(
      left: sz.width * _targetNX - r,
      top: sz.height * _targetNY - r,
      child: IgnorePointer(
        child: SizedBox(
          width: r * 2,
          height: r * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer countdown
              SizedBox(
                width: r * 2,
                height: r * 2,
                child: CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(
                      pct > 0.3 ? const Color(0xFF00C896) : const Color(0xFFFF5252)),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              // Inner glow
              Container(
                width: r * 1.4,
                height: r * 1.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00C896).withValues(alpha: 0.2),
                  border: Border.all(color: const Color(0xFF00C896), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C896).withValues(alpha: 0.5),
                      blurRadius: 24, spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.ads_click, color: Color(0xFF00C896), size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Arm Raise HUD ───────────────────────────────────────────────────
  Widget _buildArmRaiseHUD() {
    return Positioned(
      bottom: 120, left: 0, right: 0,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFFAB40).withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFFAB40).withValues(alpha: 0.15), blurRadius: 20),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fitness_center_rounded, color: Color(0xFFFFAB40), size: 28),
              const SizedBox(width: 12),
              Text('$_armRaiseReps', style: const TextStyle(
                color: Color(0xFFFFAB40), fontSize: 40, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
              const SizedBox(width: 6),
              const Text('reps', style: TextStyle(
                color: Color(0xFFFFAB40), fontSize: 16, fontFamily: 'Inter')),
            ]),
          ),
          if (!_poseDetected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 14),
                SizedBox(width: 6),
                Text('Stand back for camera to track you',
                    style: TextStyle(color: Color(0xFFFF5252), fontSize: 11, fontFamily: 'Inter')),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  HAND BOUNDING BOX WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class _HandBox extends StatelessWidget {
  final Offset position;
  final String label;
  final bool isNearTarget;

  const _HandBox({
    required this.position,
    required this.label,
    required this.isNearTarget,
  });

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    final color = isNearTarget ? const Color(0xFFFFAB40) : const Color(0xFF00C896);

    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: IgnorePointer(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Outer glow
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 2),
                    ],
                  ),
                ),
              ),
              // Corner brackets (drawn via CustomPaint)
              Positioned.fill(
                child: CustomPaint(painter: _CornerBracketPainter(color: color)),
              ),
              // Label tag
              Positioned(
                top: -16,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
                  ),
                  child: Text(label, style: const TextStyle(
                    color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900, fontFamily: 'Inter', letterSpacing: 0.5)),
                ),
              ),
              // Center dot
              Center(
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CORNER BRACKET PAINTER
// ═══════════════════════════════════════════════════════════════════════════════
class _CornerBracketPainter extends CustomPainter {
  final Color color;
  _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 16.0;
    const r = 4.0;

    // Top-left
    canvas.drawPath(Path()
      ..moveTo(0, len)..lineTo(0, r)..arcToPoint(Offset(r, 0), radius: const Radius.circular(r))..lineTo(len, 0), paint);
    // Top-right
    canvas.drawPath(Path()
      ..moveTo(size.width - len, 0)..lineTo(size.width - r, 0)..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))..lineTo(size.width, len), paint);
    // Bottom-left
    canvas.drawPath(Path()
      ..moveTo(0, size.height - len)..lineTo(0, size.height - r)..arcToPoint(Offset(r, size.height), radius: const Radius.circular(r))..lineTo(len, size.height), paint);
    // Bottom-right
    canvas.drawPath(Path()
      ..moveTo(size.width - len, size.height)..lineTo(size.width - r, size.height)..arcToPoint(Offset(size.width, size.height - r), radius: const Radius.circular(r))..lineTo(size.width, size.height - len), paint);
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GLASS BUTTON
// ═══════════════════════════════════════════════════════════════════════════════
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STAT PILL
// ═══════════════════════════════════════════════════════════════════════════════
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _StatPill({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TRACKING STATUS CHIP
// ═══════════════════════════════════════════════════════════════════════════════
class _TrackingChip extends StatelessWidget {
  final bool detected;
  const _TrackingChip({required this.detected});

  @override
  Widget build(BuildContext context) {
    final color = detected ? const Color(0xFF00C896) : const Color(0xFFFF5252);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          detected ? 'Tracking' : 'No Hands',
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Inter'),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SKELETON PAINTER
// ═══════════════════════════════════════════════════════════════════════════════
class _SkeletonPainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final Size screenSize;
  final InputImageRotation imageRotation;
  final bool isFrontCamera;

  _SkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.screenSize,
    required this.imageRotation,
    required this.isFrontCamera,
  });

  static const _connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
  ];

  Offset _toScreen(PoseLandmark lm) {
    double absW, absH;
    switch (imageRotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        absW = imageSize.height;
        absH = imageSize.width;
        break;
      default:
        absW = imageSize.width;
        absH = imageSize.height;
    }
    double nx = (lm.x / absW).clamp(0.0, 1.0);
    double ny = (lm.y / absH).clamp(0.0, 1.0);
    if (isFrontCamera) nx = 1.0 - nx;
    return Offset(nx * screenSize.width, ny * screenSize.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final jointPaint = Paint()
      ..color = const Color(0xFF00C896)
      ..style = PaintingStyle.fill;

    for (final c in _connections) {
      final a = pose.landmarks[c[0]];
      final b = pose.landmarks[c[1]];
      if (a != null && b != null && a.likelihood > 0.5 && b.likelihood > 0.5) {
        canvas.drawLine(_toScreen(a), _toScreen(b), bonePaint);
      }
    }

    for (final type in [
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
    ]) {
      final lm = pose.landmarks[type];
      if (lm != null && lm.likelihood > 0.5) {
        final p = _toScreen(lm);
        final isW = type == PoseLandmarkType.leftWrist || type == PoseLandmarkType.rightWrist;
        canvas.drawCircle(p, isW ? 7 : 4, jointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PATH PAINTER
// ═══════════════════════════════════════════════════════════════════════════════
class _PathPainter extends CustomPainter {
  final List<Offset> points;
  final int progress;
  final Size screenSize;
  _PathPainter({required this.points, required this.progress, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    for (int i = 0; i < points.length - 1; i++) {
      final a = Offset(points[i].dx * screenSize.width, points[i].dy * screenSize.height);
      final b = Offset(points[i + 1].dx * screenSize.width, points[i + 1].dy * screenSize.height);
      canvas.drawLine(a, b, Paint()
        ..color = i < progress ? const Color(0xFF00C896) : const Color(0xFF4FC3F7).withValues(alpha: 0.4)
        ..strokeWidth = i < progress ? 4 : 3
        ..style = PaintingStyle.stroke);
    }
    for (int i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * screenSize.width, points[i].dy * screenSize.height);
      if (i < progress) {
        canvas.drawCircle(p, 10, Paint()..color = const Color(0xFF00C896).withValues(alpha: 0.3));
        canvas.drawCircle(p, 6, Paint()..color = const Color(0xFF00C896));
      } else if (i == progress) {
        canvas.drawCircle(p, 16, Paint()..color = const Color(0xFFFFAB40).withValues(alpha: 0.25));
        canvas.drawCircle(p, 10, Paint()..color = const Color(0xFFFFAB40));
      } else {
        canvas.drawCircle(p, 7, Paint()..color = const Color(0xFF4FC3F7).withValues(alpha: 0.5));
      }
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.progress != progress;
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InstructionRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4FC3F7), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFFCDD6E8), fontSize: 14, fontFamily: 'Inter', height: 1.4),
          ),
        ),
      ],
    );
  }
}
