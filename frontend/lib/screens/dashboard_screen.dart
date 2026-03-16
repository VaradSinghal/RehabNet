/// Dashboard Screen â€“ displays all session metrics in real time.
/// Updates automatically via SessionService (Provider + ChangeNotifier).

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
            style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        actions: [
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
            // â”€â”€ Metric cards row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

            // â”€â”€ Tremor severity indicator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _SectionHeader('Tremor Severity'),
            const SizedBox(height: 10),
            _Gauge(value: ss.tremorScore / 100),

            const SizedBox(height: 24),

            // â”€â”€ Tremor intensity graph â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _SectionHeader('Tremor Intensity Over Time'),
            const SizedBox(height: 10),
            _TremorChart(history: ss.tremorHistory),

            const SizedBox(height: 24),

            // â”€â”€ Frequency readout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
      case 'High':     return const Color(0xFFFF5252);
      case 'Moderate': return const Color(0xFFFFAB40);
      default:         return const Color(0xFF00C896);
    }
  }
}

// â”€â”€ Metric card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 26),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
              Text(label, style: const TextStyle(color: Color(0xFF8892A4), fontSize: 12, fontFamily: 'Inter')),
            ],
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Section header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(color: Color(0xFFCDD6E8), fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Inter'),
      );
}

// â”€â”€ Gauge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _Gauge extends StatelessWidget {
  final double value; // 0.0 â€“ 1.0
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
                  style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
              Text('${(value * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter')),
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

// â”€â”€ Tremor chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        child: const Text('Waiting for data...', style: TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter')),
      );
    }

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), (e.value['intensity'] as num).toDouble()))
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
            getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF1E2840), strokeWidth: 1),
            getDrawingVerticalLine: (_) => const FlLine(color: Color(0xFF1E2840), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                    style: const TextStyle(color: Color(0xFF8892A4), fontSize: 10, fontFamily: 'Inter')),
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
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

// â”€â”€ Live readings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
          Text(label, style: const TextStyle(color: Color(0xFF8892A4), fontSize: 13, fontFamily: 'Inter')),
          Text('${value.toStringAsFixed(3)} $unit',
              style: const TextStyle(color: Color(0xFFCDD6E8), fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Inter')),
        ],
      );
}
