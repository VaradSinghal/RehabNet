/// Session service — ChangeNotifier that holds all live session metrics.
/// Feeds from SocketService streams so the UI refreshes automatically.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'socket_service.dart';

class SessionService extends ChangeNotifier {
  final SocketService _socket = SocketService();

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

  // ── Subscriptions ────────────────────────────────────────────────────
  late final StreamSubscription _tremorSub;
  late final StreamSubscription _metricsSub;

  SessionService() {
    _tremorSub = _socket.tremorStream.listen(_onTremor);
    _metricsSub = _socket.metricsStream.listen(_onMetrics);
  }

  void _onTremor(Map<String, dynamic> d) {
    tremorIntensity = (d['tremor_intensity'] as num?)?.toDouble() ?? 0.0;
    tremorFreqHz    = (d['tremor_freq_hz']   as num?)?.toDouble() ?? 0.0;
    tremorScore     = (d['severity_score']   as num?)?.toDouble() ?? 0.0;
    tremorLabel     = d['severity_label'] as String? ?? 'Low';
    accelX          = (d['accelerometer_x']  as num?)?.toDouble() ?? 0.0;
    accelY          = (d['accelerometer_y']  as num?)?.toDouble() ?? 0.0;
    accelZ          = (d['accelerometer_z']  as num?)?.toDouble() ?? 0.0;

    tremorHistory.add({
      't': tremorHistory.length.toDouble(),
      'intensity': tremorIntensity,
      'score': tremorScore,
    });
    if (tremorHistory.length > 60) tremorHistory.removeAt(0);

    notifyListeners();
  }

  void _onMetrics(Map<String, dynamic> d) {
    reps          = (d['reps']              as num?)?.toInt()    ?? reps;
    avgAccuracy   = (d['avg_accuracy_pct']  as num?)?.toDouble() ?? avgAccuracy;
    durationSec   = (d['duration_s']        as num?)?.toDouble() ?? durationSec;
    sessionActive = d['session_active']     as bool?             ?? sessionActive;
    notifyListeners();
  }

  @override
  void dispose() {
    _tremorSub.cancel();
    _metricsSub.cancel();
    super.dispose();
  }
}
