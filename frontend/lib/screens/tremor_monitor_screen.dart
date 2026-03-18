/// Tremor Monitor Screen
/// Shows animated gauge + 4-series fl_chart line chart + severity badge.
/// Data flows from SessionService (SocketIO â†’ backend ESP32 simulator).

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/session_service.dart';
import '../widgets/severity_badge.dart';

class TremorMonitorScreen extends StatelessWidget {
  const TremorMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ss = context.watch<SessionService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1221),
        title: const Text('Tremor Monitor',
            style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16), child: SeverityBadge(label: ss.tremorLabel)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // â”€â”€ Gauge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Center(
              child: SizedBox(
                width: 220,
                height: 220,
                child: CustomPaint(
                  painter: _GaugePainter(value: ss.tremorScore / 100),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      Text(
                        ss.tremorScore.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, fontFamily: 'Inter'),
                      ),
                      Text('/ 100', style: const TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter', fontSize: 13)),
                      const SizedBox(height: 8),
                      SeverityBadge(label: ss.tremorLabel),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Frequency chip
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF131929),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF4FC3F7).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${ss.tremorFreqHz.toStringAsFixed(1)} Hz',
                  style: const TextStyle(color: Color(0xFF4FC3F7), fontWeight: FontWeight.w700, fontFamily: 'Inter'),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Live Accelerometer Chart
            const Text('Live Accelerometer (X, Y, Z)',
                style: TextStyle(color: Color(0xFFCDD6E8), fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
            const SizedBox(height: 10),
            _AccelChart(history: ss.tremorHistory),

            const SizedBox(height: 24),

            // Tremor Intensity Chart
            const Text('Tremor Intensity History',
                style: TextStyle(color: Color(0xFFCDD6E8), fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
            const SizedBox(height: 10),
            _IntensityChart(history: ss.tremorHistory),

            const SizedBox(height: 24),

            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                _LegendDot(color: Color(0xFFFF5252), label: 'X'),
                SizedBox(width: 12),
                _LegendDot(color: Color(0xFF00C896), label: 'Y'),
                SizedBox(width: 12),
                _LegendDot(color: Color(0xFF4FC3F7), label: 'Z'),
              ],
            ),

            const SizedBox(height: 24),

            // Threshold info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF131929),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E2840)),
              ),
              child: const Column(
                children: [
                   _ThresholdRow('Low',       '< 30',    Color(0xFF00C896)),
                   _ThresholdRow('Moderate',  '30 – 65', Color(0xFFFFAB40)),
                   _ThresholdRow('High',      '> 65',    Color(0xFFFF5252)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Arc gauge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GaugePainter extends CustomPainter {
  final double value; // 0..1
  _GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.42;

    final bgPaint = Paint()
      ..color = const Color(0xFF1E2840)
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
          colors: [Color(0xFF00C896), Color(0xFFFFAB40), Color(0xFFFF5252)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    const startAngle = 135 * math.pi / 180;
    const sweepFull  = 270 * math.pi / 180;

    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle, sweepFull, false, bgPaint);

    if (value > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          startAngle, sweepFull * value.clamp(0, 1), false, fgPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

// â”€â”€ Accel chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _AccelChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _AccelChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Container(
        height: 150,
        decoration: BoxDecoration(color: const Color(0xFF131929), borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.center,
        child: const Text('Waiting for sensor data...', style: TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter')),
      );
    }

    List<FlSpot> xSpots = [];
    List<FlSpot> ySpots = [];
    List<FlSpot> zSpots = [];

    for (int i = 0; i < history.length; i++) {
        final d = history[i];
        xSpots.add(FlSpot(i.toDouble(), (d['ax'] as num?)?.toDouble() ?? 0));
        ySpots.add(FlSpot(i.toDouble(), (d['ay'] as num?)?.toDouble() ?? 0));
        zSpots.add(FlSpot(i.toDouble(), (d['az'] as num?)?.toDouble() ?? 0));
    }

    return Container(
      height: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2840)),
      ),
      child: LineChart(LineChartData(
        minY: -2, maxY: 2, // Gravity varies, but raw spikes usually stay in this range
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF1E2840), strokeWidth: 1),
          getDrawingVerticalLine:   (_) => const FlLine(color: Color(0xFF1E2840), strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(
          leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          _line(xSpots, const Color(0xFFFF5252)),
          _line(ySpots, const Color(0xFF00C896)),
          _line(zSpots, const Color(0xFF4FC3F7)),
        ],
      )),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    isCurved: true,
    color: color,
    barWidth: 1.5,
    dotData: const FlDotData(show: false),
  );
}

class _IntensityChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _IntensityChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox(height: 100);

    final spots = history.asMap().entries.map((e) => 
      FlSpot(e.key.toDouble(), (e.value['intensity'] as num?)?.toDouble() ?? 0)
    ).toList();

    return Container(
      height: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2840)),
      ),
      child: LineChart(LineChartData(
        minY: 0, maxY: 100,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(
          leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFFFFAB40),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: const Color(0xFFFFAB40).withValues(alpha: 0.1)),
          ),
        ],
      )),
    );
  }
}

// â”€â”€ Legend dot â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter', fontSize: 12)),
    ],
  );
}

// â”€â”€ Threshold row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ThresholdRow extends StatelessWidget {
  final String label;
  final String range;
  final Color color;
  const _ThresholdRow(this.label, this.range, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 12),
        Text(label,  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
        const Spacer(),
        Text('Score $range', style: const TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter', fontSize: 12)),
      ],
    ),
  );
}
