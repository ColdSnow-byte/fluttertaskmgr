#include "system_monitor.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dxgi.h>
#include <pdh.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr char kChannelName[] = "pureflutter/system_monitor";

flutter::EncodableValue Key(const char* text) {
  return flutter::EncodableValue(std::string(text));
}

std::string Utf8FromWide(const std::wstring& text) {
  if (text.empty()) {
    return std::string();
  }
  const int size =
      ::WideCharToMultiByte(CP_UTF8, 0, text.data(),
                            static_cast<int>(text.size()), nullptr, 0, nullptr,
                            nullptr);
  std::string result(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), size, nullptr, nullptr);
  // 去掉结尾多余的 '\0'
  while (!result.empty() && result.back() == '\0') {
    result.pop_back();
  }
  return result;
}

// ---------------------------------------------------------------------------
// PDH 性能计数器
// ---------------------------------------------------------------------------

struct Counters {
  PDH_HQUERY query = nullptr;
  PDH_HCOUNTER cpu = nullptr;
  PDH_HCOUNTER gpu = nullptr;
  PDH_HCOUNTER gpu_memory = nullptr;
  PDH_HCOUNTER gpu_committed = nullptr;
  bool initialized = false;
};

Counters& CountersInstance() {
  static Counters counters;
  return counters;
}

void EnsureCounters() {
  Counters& counters = CountersInstance();
  if (counters.initialized) {
    return;
  }
  counters.initialized = true;  // 只尝试一次，失败就退回全 0

  if (::PdhOpenQueryW(nullptr, 0, &counters.query) != ERROR_SUCCESS) {
    counters.query = nullptr;
    return;
  }

  // 用 English 接口添加，避免中文系统下计数器名被本地化导致找不到。
  // CPU：Processor Utility 与任务管理器的口径一致（已考虑睿频）。
  if (::PdhAddEnglishCounterW(
          counters.query,
          L"\\Processor Information(_Total)\\% Processor Utility", 0,
          &counters.cpu) != ERROR_SUCCESS) {
    counters.cpu = nullptr;
    if (::PdhAddEnglishCounterW(counters.query,
                                L"\\Processor(_Total)\\% Processor Time", 0,
                                &counters.cpu) != ERROR_SUCCESS) {
      counters.cpu = nullptr;
    }
  }

  // GPU：多实例计数器，按进程/引擎拆分，需要取数组后求和。
  if (::PdhAddEnglishCounterW(counters.query,
                              L"\\GPU Engine(*)\\Utilization Percentage", 0,
                              &counters.gpu) != ERROR_SUCCESS) {
    counters.gpu = nullptr;
  }
  // 专用显存：部分驱动/设备上恒为 0，因此再取一个“已提交显存”作兜底展示。
  if (::PdhAddEnglishCounterW(counters.query,
                              L"\\GPU Adapter Memory(*)\\Dedicated Usage", 0,
                              &counters.gpu_memory) != ERROR_SUCCESS) {
    counters.gpu_memory = nullptr;
  }
  if (::PdhAddEnglishCounterW(counters.query,
                              L"\\GPU Adapter Memory(*)\\Total Committed", 0,
                              &counters.gpu_committed) != ERROR_SUCCESS) {
    counters.gpu_committed = nullptr;
  }

  if (counters.cpu == nullptr && counters.gpu == nullptr &&
      counters.gpu_memory == nullptr && counters.gpu_committed == nullptr) {
    ::PdhCloseQuery(counters.query);
    counters.query = nullptr;
    return;
  }

  // 速率类计数器需要两次采样才有值，先取一次基线。
  ::PdhCollectQueryData(counters.query);
}

double ReadDoubleCounter(PDH_HCOUNTER counter) {
  if (counter == nullptr) {
    return 0.0;
  }
  PDH_FMT_COUNTERVALUE value;
  if (::PdhGetFormattedCounterValue(counter, PDH_FMT_DOUBLE, nullptr, &value) !=
      ERROR_SUCCESS) {
    return 0.0;
  }
  if (value.doubleValue < 0.0) {
    return 0.0;
  }
  return value.doubleValue;
}

// 多实例计数器求和（GPU 各进程/引擎的使用率与显存）。
template <typename Callback>
void ReadCounterArray(PDH_HCOUNTER counter, DWORD format, Callback callback) {
  if (counter == nullptr) {
    return;
  }
  DWORD buffer_size = 0;
  DWORD item_count = 0;
  // 先取一次所需缓冲区大小（此时固定返回 PDH_MORE_DATA）。
  ::PdhGetFormattedCounterArrayW(counter, format, &buffer_size, &item_count,
                                 nullptr);
  if (buffer_size == 0) {
    return;
  }
  std::vector<BYTE> buffer(buffer_size);
  auto* items =
      reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
  if (::PdhGetFormattedCounterArrayW(counter, format, &buffer_size, &item_count,
                                     items) != ERROR_SUCCESS) {
    return;
  }
  for (DWORD i = 0; i < item_count; ++i) {
    callback(items[i]);
  }
}

double ReadGpuUsage() {
  Counters& counters = CountersInstance();
  double total = 0.0;
  ReadCounterArray(counters.gpu, PDH_FMT_DOUBLE,
                   [&total](const PDH_FMT_COUNTERVALUE_ITEM_W& item) {
                     total += item.FmtValue.doubleValue;
                   });
  // 多引擎求和可能超过 100%，与任务管理器一样截断。
  return total > 100.0 ? 100.0 : total;
}

// 多实例计数器求和（字节）。
int64_t ReadCounterLarge(PDH_HCOUNTER counter) {
  int64_t total = 0;
  ReadCounterArray(counter, PDH_FMT_LARGE,
                   [&total](const PDH_FMT_COUNTERVALUE_ITEM_W& item) {
                     total += static_cast<int64_t>(item.FmtValue.largeValue);
                   });
  return total;
}

// ---------------------------------------------------------------------------
// 静态设备信息
// ---------------------------------------------------------------------------

std::string CpuName() {
  HKEY key = nullptr;
  const LONG open = ::RegOpenKeyExW(
      HKEY_LOCAL_MACHINE,
      L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", 0, KEY_READ, &key);
  if (open != ERROR_SUCCESS) {
    return std::string();
  }

  wchar_t buffer[512] = {0};
  DWORD size = sizeof(buffer);
  DWORD type = 0;
  std::string name;
  if (::RegQueryValueExW(key, L"ProcessorNameString", nullptr, &type,
                         reinterpret_cast<LPBYTE>(buffer),
                         &size) == ERROR_SUCCESS &&
      type == REG_SZ) {
    name = Utf8FromWide(std::wstring(buffer, size / sizeof(wchar_t)));
  }
  ::RegCloseKey(key);
  return name;
}

struct GpuDescription {
  std::string name;
  int64_t dedicated_bytes = 0;
};

GpuDescription PrimaryGpu() {
  GpuDescription result;
  IDXGIFactory1* factory = nullptr;
  if (FAILED(::CreateDXGIFactory1(
          __uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory))) ||
      factory == nullptr) {
    return result;
  }

  for (UINT index = 0;; ++index) {
    IDXGIAdapter1* adapter = nullptr;
    if (factory->EnumAdapters1(index, &adapter) == DXGI_ERROR_NOT_FOUND) {
      break;
    }
    if (adapter != nullptr) {
      DXGI_ADAPTER_DESC1 description;
      // 取显存最大的适配器（独显优先）。
      if (SUCCEEDED(adapter->GetDesc1(&description)) &&
          static_cast<int64_t>(description.DedicatedVideoMemory) >=
              result.dedicated_bytes) {
        result.dedicated_bytes =
            static_cast<int64_t>(description.DedicatedVideoMemory);
        result.name = Utf8FromWide(description.Description);
      }
      adapter->Release();
    }
  }
  factory->Release();
  return result;
}

flutter::EncodableMap CollectDeviceInfo() {
  SYSTEM_INFO system_info;
  ::GetSystemInfo(&system_info);

  MEMORYSTATUSEX memory;
  memory.dwLength = sizeof(memory);
  ::GlobalMemoryStatusEx(&memory);

  const GpuDescription gpu = PrimaryGpu();

  flutter::EncodableMap info;
  info[Key("cpuName")] = flutter::EncodableValue(CpuName());
  info[Key("gpuName")] = flutter::EncodableValue(gpu.name);
  info[Key("processorCount")] = flutter::EncodableValue(
      static_cast<int64_t>(system_info.dwNumberOfProcessors));
  info[Key("totalMemoryBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(memory.ullTotalPhys));
  info[Key("gpuDedicatedBytes")] =
      flutter::EncodableValue(gpu.dedicated_bytes);
  return info;
}

flutter::EncodableMap CollectPerformance() {
  EnsureCounters();
  Counters& counters = CountersInstance();
  if (counters.query != nullptr) {
    ::PdhCollectQueryData(counters.query);
  }

  MEMORYSTATUSEX memory;
  memory.dwLength = sizeof(memory);
  ::GlobalMemoryStatusEx(&memory);

  const int64_t total_memory = static_cast<int64_t>(memory.ullTotalPhys);
  const int64_t used_memory =
      total_memory - static_cast<int64_t>(memory.ullAvailPhys);
  const double memory_percent =
      total_memory > 0
          ? static_cast<double>(used_memory) /
                static_cast<double>(total_memory) * 100.0
          : 0.0;

  flutter::EncodableMap snapshot;
  snapshot[Key("cpuPercent")] =
      flutter::EncodableValue(ReadDoubleCounter(counters.cpu));
  snapshot[Key("gpuPercent")] = flutter::EncodableValue(ReadGpuUsage());
  snapshot[Key("gpuDedicatedUsedBytes")] =
      flutter::EncodableValue(ReadCounterLarge(counters.gpu_memory));
  snapshot[Key("gpuCommittedBytes")] =
      flutter::EncodableValue(ReadCounterLarge(counters.gpu_committed));
  snapshot[Key("memoryTotalBytes")] = flutter::EncodableValue(total_memory);
  snapshot[Key("memoryUsedBytes")] = flutter::EncodableValue(used_memory);
  snapshot[Key("memoryPercent")] = flutter::EncodableValue(memory_percent);
  return snapshot;
}

}  // namespace

void RegisterSystemMonitor(flutter::FlutterEngine* engine) {
  static auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string& method = call.method_name();
        if (method == "getDeviceInfo") {
          result->Success(flutter::EncodableValue(CollectDeviceInfo()));
          return;
        }
        if (method == "getPerformance") {
          result->Success(flutter::EncodableValue(CollectPerformance()));
          return;
        }
        result->NotImplemented();
      });
}
