import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_websocket_service.dart';

/// Central state manager for all live session metrics.
/// Listens to the WebSocket stream for tremor updates and exposes
/// everything the UI needs via ChangeNotifier.
///
/// Works gracefully even when the backend is unreachable — the dashboard
/// will show placeholder zeros instead of crashing.
class SessionService extends ChangeNotifier {
  final ApiWebSocketService _ws = ApiWebSocketService();

  // ── Tremor ──────────────────────────────────────────────────────────
  double tremorIntensity = 0.0;
  double tremorFreqHz    = 0.0;
  double tremorScore     = 0.0;
  String tremorLabel     = 'Low';
  double accelX          = 0.0;
  double accelY          = 0.0;
  double accelZ          = 0.0;

  final List<Map<String, dynamic>> tremorHistory = [];

  // ── Session ─────────────────────────────────────────────────────────
  int    reps          = 0;
  double avgAccuracy   = 0.0;
  double durationSec   = 0.0;
  bool   sessionActive = false;
  Timer? _sessionTimer;

  // ── Connection ──────────────────────────────────────────────────────
  bool get isConnected => _ws.isConnected.value;

  SessionService() {
    _initSafely();
  }

  void _initSafely() {
    try {
      _ws.initialize();
      _ws.tremorDataStream.addListener(_onTremorUpdate);
      _ws.isConnected.addListener(_onConnectionChange);
    } catch (e) {
      debugPrint('[SessionService] Init error (non-fatal): $e');
    }
  }

  void _onConnectionChange() {
    notifyListeners(); // So the dashboard can show a connection indicator
  }

  void _onTremorUpdate() {
    final d = _ws.tremorDataStream.value;
    if (d == null) return;

    // Use num to safely handle both int (e.g. 0) and double from JSON
    tremorFreqHz = (d['frequency_hz'] as num?)?.toDouble() ?? 0.0;
    final rawAmp = (d['amplitude'] as num?)?.toDouble() ?? 0.0;
    tremorScore  = (rawAmp * 100.0).clamp(0.0, 100.0);
    tremorLabel  = d['severity']      as String? ?? 'Low';
    accelX       = (d['accelerometer_x'] as num?)?.toDouble() ?? 0.0;
    accelY       = (d['accelerometer_y'] as num?)?.toDouble() ?? 0.0;
    accelZ       = (d['accelerometer_z'] as num?)?.toDouble() ?? 0.0;


    tremorHistory.add({
      't': tremorHistory.length.toDouble(),
      'intensity': tremorScore,
      'score': tremorScore,
    });
    if (tremorHistory.length > 60) tremorHistory.removeAt(0);

    notifyListeners();
  }

  // ── Exercise helpers (called from AR/VR screens) ────────────────────
  void addRep({double accuracy = 100.0}) {
    reps++;
    // Running average
    avgAccuracy = ((avgAccuracy * (reps - 1)) + accuracy) / reps;
    notifyListeners();
  }

  void updateMetrics({int? newReps, double? newAccuracy, bool? isActive}) {
    if (newReps != null) reps = newReps;
    if (newAccuracy != null) avgAccuracy = newAccuracy;
    if (isActive != null) sessionActive = isActive;
    notifyListeners();
  }

  // ── Session lifecycle ───────────────────────────────────────────────
  Future<void> startSession(int userId) async {
    sessionActive = true;
    reps = 0;
    avgAccuracy = 0.0;
    durationSec = 0.0;
    tremorHistory.clear();

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      durationSec++;
      notifyListeners();
    });

    try {
      await _ws.api.startSession(userId);
    } catch (e) {
      debugPrint('[SessionService] Could not start remote session: $e');
    }
    notifyListeners();
  }

  Future<void> endSession() async {
    sessionActive = false;
    _sessionTimer?.cancel();
    _sessionTimer = null;

    try {
      await _ws.api.endSession(
        exerciseCount: reps,
        avgAccuracy: avgAccuracy,
        avgTremorScore: tremorScore,
      );
    } catch (e) {
      debugPrint('[SessionService] Could not end remote session: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ws.tremorDataStream.removeListener(_onTremorUpdate);
    _ws.isConnected.removeListener(_onConnectionChange);
    _ws.disconnect();
    _sessionTimer?.cancel();
    super.dispose();
  }
}
