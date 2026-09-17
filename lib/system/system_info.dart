/// 静态设备信息。
class DeviceInfo {
  const DeviceInfo({
    required this.cpuName,
    required this.gpuName,
    required this.processorCount,
    required this.totalMemoryBytes,
    required this.gpuDedicatedBytes,
  });

  factory DeviceInfo.fromMap(Map<dynamic, dynamic> map) => DeviceInfo(
        cpuName: map['cpuName'] as String? ?? '未知处理器',
        gpuName: map['gpuName'] as String? ?? '未知显卡',
        processorCount: map['processorCount'] as int? ?? 0,
        totalMemoryBytes: map['totalMemoryBytes'] as int? ?? 0,
        gpuDedicatedBytes: map['gpuDedicatedBytes'] as int? ?? 0,
      );

  final String cpuName;
  final String gpuName;
  final int processorCount;
  final int totalMemoryBytes;

  /// 独显专用显存（集成显卡通常为 0）。
  final int gpuDedicatedBytes;

  bool get hasGpuMemory => gpuDedicatedBytes > 0;

  String get totalMemoryText => _formatBytes(totalMemoryBytes);
  String get gpuDedicatedText => _formatBytes(gpuDedicatedBytes);
}

/// 一次性能采样。
class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.cpuPercent,
    required this.gpuPercent,
    required this.memoryPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.gpuDedicatedUsedBytes,
    required this.gpuCommittedBytes,
  });

  factory PerformanceSnapshot.fromMap(Map<dynamic, dynamic> map) =>
      PerformanceSnapshot(
        cpuPercent: (map['cpuPercent'] as num? ?? 0).toDouble(),
        gpuPercent: (map['gpuPercent'] as num? ?? 0).toDouble(),
        memoryPercent: (map['memoryPercent'] as num? ?? 0).toDouble(),
        memoryUsedBytes: map['memoryUsedBytes'] as int? ?? 0,
        memoryTotalBytes: map['memoryTotalBytes'] as int? ?? 0,
        gpuDedicatedUsedBytes: map['gpuDedicatedUsedBytes'] as int? ?? 0,
        gpuCommittedBytes: map['gpuCommittedBytes'] as int? ?? 0,
      );

  final double cpuPercent;
  final double gpuPercent;
  final double memoryPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final int gpuDedicatedUsedBytes;

  /// 已提交显存（专用 + 共享）。部分驱动上“专用显存”恒为 0，这里作为兜底展示。
  final int gpuCommittedBytes;

  String get memoryUsedText => _formatBytes(memoryUsedBytes);
  String get memoryTotalText => _formatBytes(memoryTotalBytes);
  String get gpuDedicatedUsedText => _formatBytes(gpuDedicatedUsedBytes);
  String get gpuCommittedText => _formatBytes(gpuCommittedBytes);
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 GB';
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
