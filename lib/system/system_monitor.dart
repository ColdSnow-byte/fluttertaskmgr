import 'dart:io' as io;

import 'package:flutter/services.dart';

import 'system_info.dart';

/// 系统性能监控（CPU / GPU / 内存）。
///
/// 原生实现见 windows/runner/system_monitor.cpp。
class SystemMonitor {
  SystemMonitor._();

  static const MethodChannel _channel =
      MethodChannel('pureflutter/system_monitor');

  static bool get isSupported => io.Platform.isWindows;

  /// CPU 型号、显卡型号、内存与显存等静态信息。
  static Future<DeviceInfo> getDeviceInfo() async {
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
    return DeviceInfo.fromMap(map ?? const {});
  }

  /// 取一次性能快照。
  static Future<PerformanceSnapshot> getPerformance() async {
    final map =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('getPerformance');
    return PerformanceSnapshot.fromMap(map ?? const {});
  }
}
