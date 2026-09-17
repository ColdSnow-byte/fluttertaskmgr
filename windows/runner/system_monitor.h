#ifndef RUNNER_SYSTEM_MONITOR_H_
#define RUNNER_SYSTEM_MONITOR_H_

#include <flutter/flutter_engine.h>

// 注册 "pureflutter/system_monitor" MethodChannel。
//
// 提供的方法：
//   getDeviceInfo()  -> Map  CPU/GPU 型号、核心数、物理内存、显存等静态信息
//   getPerformance() -> Map  CPU 使用率、GPU 使用率/显存占用、内存占用
void RegisterSystemMonitor(flutter::FlutterEngine* engine);

#endif  // RUNNER_SYSTEM_MONITOR_H_
