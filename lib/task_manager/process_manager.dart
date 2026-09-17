import 'dart:io' as io;

import 'package:flutter/services.dart';

import 'process_info.dart';

/// Windows 进程管理的通道封装。
///
/// 原生实现见 windows/runner/process_manager.cpp。
class ProcessManager {
  ProcessManager._();

  static const MethodChannel _channel =
      MethodChannel('pureflutter/process_manager');

  /// 只有 Windows 端注册了该通道。
  static bool get isSupported => io.Platform.isWindows;

  /// 当前进程自身的 PID（用于禁止自杀）。
  static int get selfPid => io.pid;

  /// 抓取一次进程快照。
  static Future<List<ProcessEntry>> getProcesses() async {
    final result = await _channel.invokeMethod<List<dynamic>>('getProcesses');
    if (result == null) return const [];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(ProcessEntry.fromMap)
        .toList();
  }

  /// 结束进程。
  ///
  /// [force] 为 false 时先向该进程的顶层窗口发送 WM_CLOSE（优雅退出），
  /// 没有窗口或强制时直接 TerminateProcess。
  static Future<bool> killProcess(int pid, {bool force = true}) async {
    final ok = await _channel.invokeMethod<bool>(
      'killProcess',
      <String, dynamic>{'pid': pid, 'force': force},
    );
    return ok ?? false;
  }

  /// 启动程序 / 打开文件 / 打开网址（内部走 ShellExecuteW）。
  static Future<bool> launch(
    String path, {
    String? arguments,
    String? workingDirectory,
  }) async {
    final ok = await _channel.invokeMethod<bool>(
      'launch',
      <String, dynamic>{
        'path': path,
        'arguments': ?arguments,
        'workingDirectory': ?workingDirectory,
      },
    );
    return ok ?? false;
  }

  /// 在资源管理器中选中该进程的可执行文件。
  static Future<bool> revealProcess(int pid) async {
    final ok = await _channel.invokeMethod<bool>(
      'revealProcess',
      <String, dynamic>{'pid': pid},
    );
    return ok ?? false;
  }
}
