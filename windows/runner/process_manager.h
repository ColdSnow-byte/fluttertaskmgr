#ifndef RUNNER_PROCESS_MANAGER_H_
#define RUNNER_PROCESS_MANAGER_H_

#include <flutter/flutter_engine.h>

// 注册 "pureflutter/process_manager" MethodChannel。
//
// 提供的方法：
//   getProcesses()            -> List<Map>  进程快照（pid/名称/路径/内存/CPU…）
//   killProcess(pid, force)   -> bool       结束进程（force=false 时先请求关闭窗口）
//   launch(path, args, dir)   -> bool       启动程序 / 打开文件
//   revealProcess(pid)        -> bool       在资源管理器中定位进程的可执行文件
void RegisterProcessManager(flutter::FlutterEngine* engine);

#endif  // RUNNER_PROCESS_MANAGER_H_
