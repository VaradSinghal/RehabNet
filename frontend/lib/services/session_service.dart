import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_websocket_service.dart';

class SessionService extends ChangeNotifier {
  final ApiWebSocketService _apiWebSocket = ApiWebSocketService();

  // ── Tremor ──────────────────────────────────────────────────────────
  double tremorIntensity   = 0.0;
  double tremorFreqHz      = 0.0;
  double tremorScore       = 0.0;
  String tremorLabel       = 'Low';
  double accelX            = 0.0;
  double accelY            = 0.0;
  double accelZ            = 0.0;

  final List<Map<String, dynamic>> tremorHistory = [];  // rolling 60 entries

  // ── Session ─────────────────────────────────────────────────────────
  int    reps              = 0;
  double avgAccuracy       = 0.0;
  double durationSec       = 0.0;
  bool   sessionActive     = false;
  Timer? _sessionTimer;

  SessionService() {
    _apiWebSocket.initialize();
    _apiWebSocket.tremorDataStream.addListener(_onTremorUpdate);
  }

  void _onTremorUpdate() {
    final d = _apiWebSocket.tremorDataStream.value;
    if (d == null) return;

    tremorFreqHz    = (d['frequency_hz']     as num?)?.toDouble() ?? 0.0;
    tremorScore     = (d['amplitude']        as num?)?.toDouble() ?? 0.0;
    tremorLabel     = d['severity']          as String? ?? 'Low';
    
    // Fallbacks if not provided in the new websocket payload
    accelX          = (d['accelerometer_x']  as num?)?.toDouble() ?? 0.0;
    accelY          = (d['accelerometer_y']  as num?)?.toDouble() ?? 0.0;
    accelZ          = (d['accelerometer_z']  as num?)?.toDouble() ?? 0.0;

    tremorHistory.add({
      't': tremorHistory.length.toDouble(),
      'intensity': tremorScore,
      'score': tremorScore,
    });
    
    if (tremorHistory.length > 60) tremorHistory.removeAt(0);

    notifyListeners();
  }

  void updateMetrics({int? newReps, double? newAccuracy, bool? isActive}) {
    if (newReps != null) reps = newReps;
    if (newAccuracy != null) avgAccuracy = newAccuracy;
    if (isActive != null) sessionActive = isActive;
    notifyListeners();
  }

  Future<void> startSession(int userId) async {
    sessionActive = true;
    reps = 0;
    avgAccuracy = 0.0;
    durationSec = 0.0;
    tremorHistory.clear();
    
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      durationSec++;
      notifyListeners();
    });

    await _apiWebSocket.api.startSession(userId);
    notifyListeners();
  }

  Future<void> endSession() async {
    sessionActive = false;
    _sessionTimer?.cancel();
    _sessionTimer = null;

    await _apiWebSocket.api.endSession(
        exerciseCount: reps,
        avgAccuracy: avgAccuracy,
        avgTremorScore: tremorScore,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _apiWebSocket.tremorDataStream.removeListener(_onTremorUpdate);
    _apiWebSocket.disconnect();
    _sessionTimer?.cancel();
    super.dispose();
  }
}
