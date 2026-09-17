/// 一条进程快照。
class ProcessEntry {
  const ProcessEntry({
    required this.pid,
    required this.parentPid,
    required this.name,
    required this.path,
    required this.memoryBytes,
    required this.cpuPercent,
    required this.threadCount,
    this.startTime,
  });

  factory ProcessEntry.fromMap(Map<dynamic, dynamic> map) {
    final startMillis = map['startTime'] as int? ?? 0;
    return ProcessEntry(
      pid: map['pid'] as int? ?? 0,
      parentPid: map['parentPid'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      path: map['path'] as String? ?? '',
      memoryBytes: map['memory'] as int? ?? 0,
      cpuPercent: (map['cpu'] as num? ?? 0).toDouble(),
      threadCount: map['threads'] as int? ?? 0,
      startTime: startMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(startMillis, isUtc: true).toLocal()
          : null,
    );
  }

  final int pid;
  final int parentPid;
  final String name;
  final String path;

  /// 工作集大小（字节）。
  final int memoryBytes;

  /// 0 ~ 100，已按 CPU 核心数归一化（与任务管理器一致）。
  final double cpuPercent;
  final int threadCount;
  final DateTime? startTime;

  String get displayName => name.isEmpty ? 'PID $pid' : name;

  bool get hasPath => path.isNotEmpty;

  /// 目录部分，用于展示。
  String get directory {
    if (!hasPath) return '';
    final index = path.lastIndexOf('\\');
    return index <= 0 ? path : path.substring(0, index);
  }

  String get memoryText {
    const mb = 1024 * 1024;
    if (memoryBytes >= mb) {
      return '${(memoryBytes / mb).toStringAsFixed(1)} MB';
    }
    return '${(memoryBytes / 1024).toStringAsFixed(0)} KB';
  }

  String get cpuText => '${cpuPercent.toStringAsFixed(1)}%';
}
