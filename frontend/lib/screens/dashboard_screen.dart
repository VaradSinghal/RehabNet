/// Dashboard Screen — displays all session metrics in real time.
/// Updates automatically via SessionService (Provider + ChangeNotifier).
/// Shows useful placeholder content when no backend/sensor is connected.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/session_service.dart';
import '../widgets/severity_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ss = context.watch<SessionService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1221),
        title: const Text('Patient Dashboard',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600)),
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ss.isConnected
                        ? const Color(0xFF00C896)
                        : const Color(0xFFFF5252),
                    boxShadow: [
                      BoxShadow(
                        color: (ss.isConnected
                                ? const Color(0xFF00C896)
                                : const Color(0xFFFF5252))
                            .withValues(alpha: 0.5),
                        blurRadius: 6,
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ss.isConnected ? 'Live' : 'Offline',
                  style: TextStyle(
                    color: ss.isConnected
                        ? const Color(0xFF00C896)
                        : const Color(0xFF8892A4),
                    fontSize: 11,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SeverityBadge(label: ss.tremorLabel),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Session control ─────────────────────────────────────
            _SessionControl(ss: ss),

            const SizedBox(height: 16),

            // ── Metric cards row ────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _MetricCard(
                  icon: Icons.fitness_center,
                  label: 'Repetitions',
                  value: '${ss.reps}',
                  color: const Color(0xFF00C896),
                ),
                _MetricCard(
                  icon: Icons.track_changes,
                  label: 'Accuracy',
                  value: '${ss.avgAccuracy.toStringAsFixed(1)}%',
                  color: const Color(0xFF4FC3F7),
                ),
                _MetricCard(
                  icon: Icons.timer,
                  label: 'Session Time',
                  value: _formatDuration(ss.durationSec),
                  color: const Color(0xFFFFAB40),
                ),
                _MetricCard(
                  icon: Icons.vibration,
                  label: 'Tremor Score',
                  value: ss.tremorScore.toStringAsFixed(1),
                  color: _tremorColor(ss.tremorLabel),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Tremor severity indicator ────────────────────────────
            _SectionHeader('Tremor Severity'),
            const SizedBox(height: 10),
            _Gauge(value: ss.tremorScore / 100),

            const SizedBox(height: 24),

            // ── Tremor intensity graph ──────────────────────────────
            _SectionHeader('Tremor Intensity Over Time'),
            const SizedBox(height: 10),
            _TremorChart(history: ss.tremorHistory),

            const SizedBox(height: 24),

            // ── Frequency readout ───────────────────────────────────
            _SectionHeader('Live Sensor Readings'),
            const SizedBox(height: 10),
            _LiveReadings(ss: ss),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(double secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static Color _tremorColor(String label) {
    switch (label) {
      case 'High':
        return const Color(0xFFFF5252);
      case 'Moderate':
        return const Color(0xFFFFAB40);
      default:
        return const Color(0xFF00C896);
    }
  }
}

// ── Session Control Card ──────────────────────────────────────────────────────
class _SessionControl extends StatelessWidget {
  final SessionService ss;
  const _SessionControl({required this.ss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ss.sessionActive
              ? [const Color(0xFF00C896).withValues(alpha: 0.12), const Color(0xFF131929)]
              : [const Color(0xFF131929), const Color(0xFF131929)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ss.sessionActive
              ? const Color(0xFF00C896).withValues(alpha: 0.4)
              : const Color(0xFF1E2840),
        ),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ss.sessionActive
                  ? const Color(0xFF00C896).withValues(alpha: 0.2)
                  : const Color(0xFF1E2840),
            ),
            child: Icon(
              ss.sessionActive ? Icons.play_circle_fill_rounded : Icons.play_arrow_rounded,
              color: ss.sessionActive ? const Color(0xFF00C896) : const Color(0xFF4A5568),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ss.sessionActive ? 'Session Active' : 'No Session',
                  style: TextStyle(
                    color: ss.sessionActive ? Colors.white : const Color(0xFF8892A4),
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    fontSize: 15,
                  ),
                ),
                Text(
                  ss.sessionActive
                      ? 'Recording exercise data...'
                      : 'Start a session to track your progress',
                  style: const TextStyle(color: Color(0xFF5A6478), fontSize: 12, fontFamily: 'Inter'),
                ),
              ],
            ),
          ),

          // Button
          ElevatedButton(
            onPressed: () {
              if (ss.sessionActive) {
                ss.endSession();
              } else {
                ss.startSession(1); // Default user ID = 1
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ss.sessionActive ? const Color(0xFFFF5252) : const Color(0xFF00C896),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              ss.sessionActive ? 'Stop' : 'Start',
              style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Metric card ───────────────────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 26),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter')),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF8892A4),
                      fontSize: 12,
                      fontFamily: 'Inter')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
            color: Color(0xFFCDD6E8),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter'),
      );
}

// ── Gauge ─────────────────────────────────────────────────────────────────────
class _Gauge extends StatelessWidget {
  final double value;
  const _Gauge({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value < 0.3
        ? const Color(0xFF00C896)
        : value < 0.65
            ? const Color(0xFFFFAB40)
            : const Color(0xFFFF5252);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(value * 100).toStringAsFixed(1)} / 100',
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter')),
              Text('${(value * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: Color(0xFF8892A4), fontFamily: 'Inter')),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF1E2840),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tremor chart ──────────────────────────────────────────────────────────────
class _TremorChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _TremorChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF131929),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_rounded,
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.4), size: 40),
            const SizedBox(height: 8),
            const Text('Waiting for sensor data...',
                style: TextStyle(
                    color: Color(0xFF8892A4), fontFamily: 'Inter')),
            const SizedBox(height: 4),
            const Text('Connect your ESP32 wearable',
                style: TextStyle(
                    color: Color(0xFF5A6478),
                    fontFamily: 'Inter',
                    fontSize: 11)),
          ],
        ),
      );
    }

    final spots = history
        .asMap()
        .entries
        .map((e) =>
            FlSpot(e.key.toDouble(), (e.value['intensity'] as num).toDouble()))
        .toList();

    return Container(
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2840)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF1E2840), strokeWidth: 1),
            getDrawingVerticalLine: (_) =>
                const FlLine(color: Color(0xFF1E2840), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                    style: const TextStyle(
                        color: Color(0xFF8892A4),
                        fontSize: 10,
                        fontFamily: 'Inter')),
              ),
            ),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          minY: 0,
          maxY: 100,
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF4FC3F7),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live readings ─────────────────────────────────────────────────────────────
class _LiveReadings extends StatelessWidget {
  final SessionService ss;
  const _LiveReadings({required this.ss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2840)),
      ),
      child: Column(
        children: [
          _ReadingRow('Accel X', ss.accelX, 'g'),
          const Divider(color: Color(0xFF1E2840), height: 16),
          _ReadingRow('Accel Y', ss.accelY, 'g'),
          const Divider(color: Color(0xFF1E2840), height: 16),
          _ReadingRow('Accel Z', ss.accelZ, 'g'),
          const Divider(color: Color(0xFF1E2840), height: 16),
          _ReadingRow('Tremor Freq', ss.tremorFreqHz, 'Hz'),
        ],
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  const _ReadingRow(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8892A4),
                  fontSize: 13,
                  fontFamily: 'Inter')),
          Text('${value.toStringAsFixed(3)} $unit',
              style: const TextStyle(
                  color: Color(0xFFCDD6E8),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFamily: 'Inter')),
        ],
      );
}
