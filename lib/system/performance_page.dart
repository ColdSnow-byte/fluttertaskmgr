import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';

import 'system_info.dart';
import 'system_monitor.dart';

/// 性能页：每秒采样一次，绘制 CPU / GPU / 内存的使用率折线图。
class PerformancePage extends StatefulWidget {
  const PerformancePage({super.key});

  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage> {
  static const int _maxPoints = 60; // 保留最近 60 秒
  static const Duration _interval = Duration(seconds: 1);

  final List<double> _cpuHistory = <double>[];
  final List<double> _gpuHistory = <double>[];
  final List<double> _memoryHistory = <double>[];

  DeviceInfo? _deviceInfo;
  PerformanceSnapshot? _latest;
  String? _error;
  bool _autoRefresh = true;

  bool get _isSupported => SystemMonitor.isSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDeviceInfo();
      _scheduleNextSample();
    });
  }

  /// 递归计时：上一次采样没回来就不会叠加下一次请求。
  void _scheduleNextSample() {
    if (!mounted) return;
    Future<void>.delayed(_interval, () async {
      if (!mounted) return;
      if (_autoRefresh && _isSupported) {
        await _sample();
      }
      _scheduleNextSample();
    });
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final info = await SystemMonitor.getDeviceInfo();
      if (!mounted) return;
      setState(() => _deviceInfo = info);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _sample() async {
    try {
      final snapshot = await SystemMonitor.getPerformance();
      if (!mounted) return;
      setState(() {
        _latest = snapshot;
        _append(_cpuHistory, snapshot.cpuPercent);
        _append(_gpuHistory, snapshot.gpuPercent);
        _append(_memoryHistory, snapshot.memoryPercent);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  String _gpuDetail(DeviceInfo? info, PerformanceSnapshot? latest) {
    if (latest == null) return '读取中…';
    final committed = '已提交 ${latest.gpuCommittedText}';
    if (info != null && info.hasGpuMemory) {
      return '专用 ${latest.gpuDedicatedUsedText} / ${info.gpuDedicatedText} · $committed';
    }
    return '$committed（未检测到独显专用显存，可能为集成显卡）';
  }

  void _append(List<double> history, double value) {
    history.add(value.clamp(0.0, 100.0));
    if (history.length > _maxPoints) {
      history.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) {
      return const Center(
        child: Text(
          '性能监控仅在 Windows 端可用',
          style: TextStyle(color: CupertinoColors.systemGrey),
        ),
      );
    }

    final info = _deviceInfo;
    final latest = _latest;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DeviceCard(
          info: info,
          autoRefresh: _autoRefresh,
          onToggleRefresh: () => setState(() => _autoRefresh = !_autoRefresh),
          error: _error,
        ),
        const SizedBox(height: 12),
        _MetricCard(
          title: 'CPU',
          subtitle: info?.cpuName.trim() ?? '读取中…',
          detail: '${info?.processorCount ?? 0} 个逻辑处理器 · 每秒采样',
          valueText: '${(latest?.cpuPercent ?? 0).toStringAsFixed(0)}%',
          history: _cpuHistory,
          color: const Color(0xFF4DA3FF),
        ),
        _MetricCard(
          title: 'GPU',
          subtitle: info?.gpuName.trim() ?? '读取中…',
          detail: _gpuDetail(info, latest),
          valueText: '${(latest?.gpuPercent ?? 0).toStringAsFixed(0)}%',
          history: _gpuHistory,
          color: const Color(0xFFB46BFF),
        ),
        _MetricCard(
          title: '内存',
          subtitle: '物理内存',
          detail: latest == null
              ? '读取中…'
              : '${latest.memoryUsedText} / ${latest.memoryTotalText}'
                  '（${latest.memoryPercent.toStringAsFixed(0)}%）',
          valueText: '${(latest?.memoryPercent ?? 0).toStringAsFixed(0)}%',
          history: _memoryHistory,
          color: const Color(0xFF3DDC97),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.info,
    required this.autoRefresh,
    required this.onToggleRefresh,
    this.error,
  });

  final DeviceInfo? info;
  final bool autoRefresh;
  final VoidCallback onToggleRefresh;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '设备信息',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              CupertinoButton(
                minimumSize: const Size(32, 32),
                padding: const EdgeInsets.all(4),
                onPressed: onToggleRefresh,
                child: Icon(
                  autoRefresh ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  size: 18,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _InfoLine(label: 'CPU', value: info?.cpuName.trim() ?? '读取中…'),
          _InfoLine(label: 'GPU', value: info?.gpuName.trim() ?? '读取中…'),
          _InfoLine(
            label: '内存',
            value: info == null ? '读取中…' : info!.totalMemoryText,
          ),
          _InfoLine(
            label: '显存',
            value: info == null
                ? '读取中…'
                : (info!.hasGpuMemory ? info!.gpuDedicatedText : '共享内存'),
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              '采样异常：$error',
              style: const TextStyle(
                color: CupertinoColors.systemRed,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                color: CupertinoColors.systemGrey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.valueText,
    required this.history,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String detail;
  final String valueText;
  final List<double> history;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                valueText,
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            child: history.length < 2
                ? const Center(
                    child: Text(
                      '采集中…',
                      style: TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 12,
                      ),
                    ),
                  )
                : LineChart(
                    _chartData(),
                    duration: const Duration(milliseconds: 220),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _chartData() {
    final spots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), history[i]));
    }

    return LineChartData(
      minX: 0,
      maxX: (history.length - 1).toDouble(),
      minY: 0,
      maxY: 100,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (_) => FlLine(
          color: CupertinoColors.white.withValues(alpha: 0.07),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xE6000000),
          getTooltipItems: (touchedSpots) => touchedSpots
              .map((spot) => LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)}%',
                    const TextStyle(color: CupertinoColors.white, fontSize: 12),
                  ))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: color,
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.35),
                color.withValues(alpha: 0.02),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
