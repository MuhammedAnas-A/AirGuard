import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'db_helper.dart';

enum GraphType { co2, o2 }

class GraphPage extends StatefulWidget {
  final GraphType graphType;
  const GraphPage({super.key, required this.graphType});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final DbHelper _db = DbHelper();
  List<SensorReading> _readings = [];
  bool _loading = true;
  Timer? _liveTimer;

  // Filter options in minutes
  static const Map<String, int> _filters = {
    '5m': 5,
    '15m': 15,
    '30m': 30,
    '1h': 60,
    '3h': 180,
    '6h': 360,
    '12h': 720,
    '24h': 1440,
    'All': -1,
  };

  String _selectedFilter = '1h';

  @override
  void initState() {
    super.initState();
    _loadData();
    // Refresh graph every 3 seconds to match sensor polling interval
    _liveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _refreshSilently();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await _fetchReadings();
    if (mounted) setState(() => _loading = false);
  }

  /// Refresh data without showing loading spinner (for live updates)
  Future<void> _refreshSilently() async {
    await _fetchReadings();
  }

  Future<void> _fetchReadings() async {
    final minutes = _filters[_selectedFilter]!;
    final readings = minutes == -1
        ? await _db.getReadings()
        : await _db.getReadingsLastMinutes(minutes);
    if (mounted) {
      setState(() => _readings = readings);
    }
  }

  bool get _isCO2 => widget.graphType == GraphType.co2;

  String get _title => _isCO2 ? 'CO₂ Level History' : 'O₂ Level History';
  String get _unit => _isCO2 ? 'ppm' : '%';
  Color get _accentColor =>
      _isCO2 ? const Color(0xFFFFD700) : const Color(0xFF00FFA3);
  Color get _gradientEnd =>
      _isCO2 ? const Color(0xFFFF6B6B) : const Color(0xFF00D4FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1419),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF00FFA3),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [_accentColor, _gradientEnd],
          ).createShader(bounds),
          child: Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildFilterChips(),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FFA3)),
                  )
                : _readings.isEmpty
                ? _buildEmptyState()
                : _buildChart(),
          ),
          if (!_loading && _readings.isNotEmpty) _buildStats(),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _filters.keys.map((label) {
          final isSelected = _selectedFilter == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) async {
                setState(() => _selectedFilter = label);
                await _loadData();
              },
              backgroundColor: Colors.white.withOpacity(0.05),
              selectedColor: _accentColor.withOpacity(0.25),
              labelStyle: TextStyle(
                color: isSelected ? _accentColor : Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected
                    ? _accentColor.withOpacity(0.5)
                    : Colors.white10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 64,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 16),
          Text(
            'No data available for this period',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Readings are recorded every 3 seconds',
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _readings.length; i++) {
      final r = _readings[i];
      final value = _isCO2 ? r.co2 : r.o2;
      // Use timestamp in seconds from first reading as x
      final x =
          (r.timestamp.millisecondsSinceEpoch -
              _readings.first.timestamp.millisecondsSinceEpoch) /
          1000.0;
      spots.add(FlSpot(x, value));
    }

    // Calculate Y bounds
    final values = spots.map((s) => s.y);
    double minY = values.reduce((a, b) => a < b ? a : b);
    double maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.15;
    if (padding < 1) {
      minY = minY - 5;
      maxY = maxY + 5;
    } else {
      minY = minY - padding;
      maxY = maxY + padding;
    }
    if (minY < 0) minY = 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: _getHorizontalInterval(minY, maxY),
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: Colors.white.withOpacity(0.04), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      _isCO2
                          ? value.toStringAsFixed(0)
                          : value.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: _getTimeInterval(spots),
                getTitlesWidget: (value, meta) {
                  final ts = _readings.first.timestamp.add(
                    Duration(seconds: value.toInt()),
                  );
                  final format =
                      _selectedFilter == '24h' ||
                          _selectedFilter == '12h' ||
                          _selectedFilter == 'All'
                      ? DateFormat.Hm()
                      : DateFormat('HH:mm:ss');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      format.format(ts),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1E24),
              tooltipRoundedRadius: 10,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final ts = _readings.first.timestamp.add(
                    Duration(seconds: spot.x.toInt()),
                  );
                  final timeStr = DateFormat('HH:mm:ss').format(ts);
                  return LineTooltipItem(
                    '${_isCO2 ? spot.y.toStringAsFixed(0) : spot.y.toStringAsFixed(1)} $_unit\n$timeStr',
                    TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: _accentColor,
              barWidth: 2.5,
              dotData: FlDotData(
                show: spots.length < 50,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 2.5,
                      color: _accentColor,
                      strokeWidth: 1,
                      strokeColor: Colors.white24,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _accentColor.withOpacity(0.25),
                    _accentColor.withOpacity(0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),
    );
  }

  double _getHorizontalInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 10) return 2;
    if (range <= 50) return 10;
    if (range <= 200) return 50;
    if (range <= 1000) return 200;
    return 500;
  }

  double _getTimeInterval(List<FlSpot> spots) {
    if (spots.isEmpty || spots.length < 2) return 60;
    final totalSeconds = spots.last.x - spots.first.x;
    if (totalSeconds <= 60) return 10;
    if (totalSeconds <= 300) return 30;
    if (totalSeconds <= 900) return 120;
    if (totalSeconds <= 3600) return 300;
    if (totalSeconds <= 10800) return 900;
    return 3600;
  }

  Widget _buildStats() {
    if (_readings.isEmpty) return const SizedBox.shrink();

    final values = _readings.map((r) => _isCO2 ? r.co2 : r.o2).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final latest = values.last;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F1419).withOpacity(0.9),
            const Color(0xFF0D1117).withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Current',
            value: _isCO2
                ? latest.toStringAsFixed(0)
                : latest.toStringAsFixed(1),
            unit: _unit,
            color: _accentColor,
          ),
          _StatItem(
            label: 'Min',
            value: _isCO2 ? min.toStringAsFixed(0) : min.toStringAsFixed(1),
            unit: _unit,
            color: const Color(0xFF00D4FF),
          ),
          _StatItem(
            label: 'Avg',
            value: _isCO2 ? avg.toStringAsFixed(0) : avg.toStringAsFixed(1),
            unit: _unit,
            color: Colors.white70,
          ),
          _StatItem(
            label: 'Max',
            value: _isCO2 ? max.toStringAsFixed(0) : max.toStringAsFixed(1),
            unit: _unit,
            color: const Color(0xFFFF6B6B),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(unit, style: const TextStyle(color: Colors.white30, fontSize: 10)),
      ],
    );
  }
}
