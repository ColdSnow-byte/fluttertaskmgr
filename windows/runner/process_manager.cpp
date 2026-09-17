#include "process_manager.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <psapi.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>

namespace {

constexpr char kChannelName[] = "pureflutter/process_manager";

// EncodableValue 是 std::variant，直接传 const char* 会被解析成 bool，
// 所有 map 的 key / 字符串值都必须显式构造成 std::string。
flutter::EncodableValue Key(const char* text) {
  return flutter::EncodableValue(std::string(text));
}

std::string Utf8FromWide(const std::wstring& text) {
  if (text.empty()) {
    return std::string();
  }
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()), nullptr,
                                         0, nullptr, nullptr);
  std::string result(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring WideFromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), size);
  return result;
}

// FILETIME 的单位是 100ns。
uint64_t FileTimeToTicks(const FILETIME& time) {
  ULARGE_INTEGER value;
  value.LowPart = time.dwLowDateTime;
  value.HighPart = time.dwHighDateTime;
  return value.QuadPart;
}

// FILETIME(1601) -> Unix 毫秒。
int64_t FileTimeToUnixMillis(const FILETIME& time) {
  const uint64_t millis = FileTimeToTicks(time) / 10000;
  return static_cast<int64_t>(millis) - 11644473600000LL;
}

int ProcessorCount() {
  static const int count = [] {
    SYSTEM_INFO info;
    ::GetSystemInfo(&info);
    return info.dwNumberOfProcessors > 0 ? static_cast<int>(info.dwNumberOfProcessors) : 1;
  }();
  return count;
}

struct CpuSample {
  uint64_t process_time = 0;
  uint64_t system_time = 0;
};

// 上一次采样的 CPU 时间，用于计算两次刷新之间的 CPU 占用率。
std::map<DWORD, CpuSample> g_cpu_samples;

double ComputeCpuPercent(DWORD pid, HANDLE process,
                         std::map<DWORD, CpuSample>& next_samples) {
  FILETIME creation;
  FILETIME exit_time;
  FILETIME kernel;
  FILETIME user;
  if (!::GetProcessTimes(process, &creation, &exit_time, &kernel, &user)) {
    return 0.0;
  }

  FILETIME now;
  ::GetSystemTimeAsFileTime(&now);

  const uint64_t process_time = FileTimeToTicks(kernel) + FileTimeToTicks(user);
  const uint64_t system_time = FileTimeToTicks(now);
  next_samples[pid] = CpuSample{process_time, system_time};

  const auto previous = g_cpu_samples.find(pid);
  if (previous == g_cpu_samples.end()) {
    return 0.0;  // 首次采样没有基线
  }

  const uint64_t delta_process = process_time - previous->second.process_time;
  const uint64_t delta_system = system_time - previous->second.system_time;
  if (delta_system == 0) {
    return 0.0;
  }

  // 与任务管理器一致：所有进程加起来不超过 100%，因此按核心数归一化。
  double percent =
      static_cast<double>(delta_process) / static_cast<double>(delta_system) * 100.0 /
      ProcessorCount();
  if (percent < 0.0) {
    percent = 0.0;
  }
  return percent;
}

bool TryGetProcessPath(DWORD pid, std::wstring* path) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  wchar_t buffer[MAX_PATH];
  DWORD size = MAX_PATH;
  const bool ok = ::QueryFullProcessImageNameW(process, 0, buffer, &size) == TRUE;
  if (ok) {
    path->assign(buffer, size);
  }
  ::CloseHandle(process);
  return ok;
}

flutter::EncodableList CollectProcesses() {
  flutter::EncodableList processes;
  std::map<DWORD, CpuSample> next_samples;

  HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return processes;
  }

  PROCESSENTRY32W entry;
  entry.dwSize = sizeof(entry);
  if (::Process32FirstW(snapshot, &entry)) {
    do {
      const DWORD pid = entry.th32ProcessID;
      std::string path;
      uint64_t memory = 0;
      double cpu = 0.0;
      int64_t start_time = 0;

      HANDLE process =
          ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                        FALSE, pid);
      if (process == nullptr) {
        // 受保护进程拿不到 VM_READ，退回只读有限信息。
        process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
      }
      if (process != nullptr) {
        wchar_t buffer[MAX_PATH];
        DWORD size = MAX_PATH;
        if (::QueryFullProcessImageNameW(process, 0, buffer, &size)) {
          path = Utf8FromWide(std::wstring(buffer, size));
        }

        PROCESS_MEMORY_COUNTERS_EX counters;
        counters.cb = sizeof(counters);
        if (::GetProcessMemoryInfo(
                process, reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
                sizeof(counters))) {
          memory = counters.WorkingSetSize;
        }

        cpu = ComputeCpuPercent(pid, process, next_samples);

        FILETIME creation;
        FILETIME exit_time;
        FILETIME kernel;
        FILETIME user;
        if (::GetProcessTimes(process, &creation, &exit_time, &kernel, &user)) {
          start_time = FileTimeToUnixMillis(creation);
        }
        ::CloseHandle(process);
      }

      flutter::EncodableMap item;
      item[Key("pid")] = flutter::EncodableValue(static_cast<int64_t>(pid));
      item[Key("parentPid")] =
          flutter::EncodableValue(static_cast<int64_t>(entry.th32ParentProcessID));
      item[Key("name")] = flutter::EncodableValue(Utf8FromWide(entry.szExeFile));
      item[Key("path")] = flutter::EncodableValue(path);
      item[Key("memory")] = flutter::EncodableValue(static_cast<int64_t>(memory));
      item[Key("cpu")] = flutter::EncodableValue(cpu);
      item[Key("threads")] =
          flutter::EncodableValue(static_cast<int64_t>(entry.cntThreads));
      item[Key("startTime")] = flutter::EncodableValue(start_time);
      processes.push_back(flutter::EncodableValue(std::move(item)));
    } while (::Process32NextW(snapshot, &entry));
  }
  ::CloseHandle(snapshot);

  // 顺手清理已经退出的进程，避免采样表无限增长。
  g_cpu_samples.swap(next_samples);
  return processes;
}

struct CloseRequest {
  DWORD pid = 0;
  int windows = 0;
};

BOOL CALLBACK RequestCloseProc(HWND window, LPARAM lparam) {
  auto* request = reinterpret_cast<CloseRequest*>(lparam);
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  if (pid != request->pid || !::IsWindowVisible(window) ||
      ::GetWindow(window, GW_OWNER) != nullptr) {
    return TRUE;
  }
  ::PostMessage(window, WM_CLOSE, 0, 0);
  request->windows++;
  return TRUE;
}

bool KillProcess(DWORD pid, bool force) {
  if (!force) {
    CloseRequest request;
    request.pid = pid;
    ::EnumWindows(RequestCloseProc, reinterpret_cast<LPARAM>(&request));
    if (request.windows > 0) {
      return true;  // 已发出 WM_CLOSE，由程序自己决定是否退出
    }
  }

  HANDLE process = ::OpenProcess(PROCESS_TERMINATE, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  const BOOL ok = ::TerminateProcess(process, 1);
  ::CloseHandle(process);
  return ok == TRUE;
}

bool LaunchProcess(const std::wstring& path, const std::wstring& arguments,
                   const std::wstring& working_directory) {
  const wchar_t* args = arguments.empty() ? nullptr : arguments.c_str();
  const wchar_t* directory =
      working_directory.empty() ? nullptr : working_directory.c_str();
  HINSTANCE result = ::ShellExecuteW(nullptr, L"open", path.c_str(), args,
                                     directory, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(result) > 32;
}

bool RevealPath(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }
  const std::wstring parameters = L"/select,\"" + path + L"\"";
  HINSTANCE result = ::ShellExecuteW(nullptr, L"open", L"explorer.exe",
                                     parameters.c_str(), nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(result) > 32;
}

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  if (value == nullptr) {
    return nullptr;
  }
  if (!std::holds_alternative<flutter::EncodableMap>(*value)) {
    return nullptr;
  }
  return &std::get<flutter::EncodableMap>(*value);
}

int64_t IntArg(const flutter::EncodableMap& arguments, const char* key,
               int64_t fallback) {
  const auto it = arguments.find(Key(key));
  if (it == arguments.end()) {
    return fallback;
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return std::get<int64_t>(it->second);
  }
  if (std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  return fallback;
}

bool BoolArg(const flutter::EncodableMap& arguments, const char* key,
             bool fallback) {
  const auto it = arguments.find(Key(key));
  if (it == arguments.end() || !std::holds_alternative<bool>(it->second)) {
    return fallback;
  }
  return std::get<bool>(it->second);
}

std::wstring StringArg(const flutter::EncodableMap& arguments, const char* key) {
  const auto it = arguments.find(Key(key));
  if (it == arguments.end() ||
      !std::holds_alternative<std::string>(it->second)) {
    return std::wstring();
  }
  return WideFromUtf8(std::get<std::string>(it->second));
}

}  // namespace

void RegisterProcessManager(flutter::FlutterEngine* engine) {
  // MethodChannel 的析构不会注销 handler，用静态对象保证生命周期覆盖整个 App。
  static auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string& method = call.method_name();
        const flutter::EncodableMap* arguments = AsMap(call.arguments());

        if (method == "getProcesses") {
          result->Success(flutter::EncodableValue(CollectProcesses()));
          return;
        }

        if (method == "killProcess" && arguments != nullptr) {
          const DWORD pid = static_cast<DWORD>(IntArg(*arguments, "pid", 0));
          const bool force = BoolArg(*arguments, "force", true);
          result->Success(flutter::EncodableValue(
              KillProcess(pid, force)));
          return;
        }

        if (method == "launch" && arguments != nullptr) {
          const bool ok = LaunchProcess(StringArg(*arguments, "path"),
                                        StringArg(*arguments, "arguments"),
                                        StringArg(*arguments, "workingDirectory"));
          result->Success(flutter::EncodableValue(ok));
          return;
        }

        if (method == "revealProcess" && arguments != nullptr) {
          std::wstring path;
          const bool found =
              TryGetProcessPath(static_cast<DWORD>(IntArg(*arguments, "pid", 0)),
                                &path);
          result->Success(flutter::EncodableValue(found && RevealPath(path)));
          return;
        }

        result->NotImplemented();
      });
}
