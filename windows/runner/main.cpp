#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "crash_logger.h"
#include "flutter_window.h"
#include "utils.h"


namespace {

bool HasCommandLineSwitch(const std::vector<std::string>& args,
                          const char* wanted) {
  for (const auto& arg : args) {
    if (arg == wanted) return true;
  }
  return false;
}

bool IsLegacyWindowsVersion() {
  // GetVersionExW is deprecated and /WX turns its warning into a build failure.
  // RtlGetVersion reports the real kernel version on Windows 7 through 11.
  using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return false;
  }

  const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
      GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) {
    return false;
  }

  OSVERSIONINFOW version{};
  version.dwOSVersionInfoSize = sizeof(version);
  if (rtl_get_version(&version) != 0) {
    return false;
  }

  return version.dwMajorVersion < 6 ||
         (version.dwMajorVersion == 6 && version.dwMinorVersion <= 3);
}

bool IsBasicDisplayAdapter() {
  DISPLAY_DEVICEW device{};
  device.cb = sizeof(device);

  for (DWORD index = 0; EnumDisplayDevicesW(nullptr, index, &device, 0);
       ++index) {
    if (device.StateFlags & DISPLAY_DEVICE_MIRRORING_DRIVER) {
      continue;
    }

    const wchar_t* name = device.DeviceString;
    if (name == nullptr || *name == L'\0') {
      continue;
    }

    if (wcsstr(name, L"Microsoft Basic Display Adapter") != nullptr ||
        wcsstr(name, L"Standard VGA Graphics Adapter") != nullptr ||
        wcsstr(name, L"标准 VGA 图形适配器") != nullptr ||
        wcsstr(name, L"Microsoft 基本显示适配器") != nullptr) {
      return true;
    }
  }

  // If Windows reports no usable display adapter, prefer CPU rendering.
  device = {};
  device.cb = sizeof(device);
  return !EnumDisplayDevicesW(nullptr, 0, &device, 0);
}

bool RelaunchWithSoftwareRenderingIfNeeded(
    const std::vector<std::string>& args) {
  if (HasCommandLineSwitch(args, "--enable-software-rendering")) {
    return true;
  }

  if (!IsLegacyWindowsVersion() && !IsBasicDisplayAdapter()) {
    return true;
  }

  wchar_t executable[MAX_PATH] = {};
  const DWORD length =
      GetModuleFileNameW(nullptr, executable, _countof(executable));
  if (length == 0 || length >= _countof(executable)) {
    reader_crash::LogError(
        L"兼容模式启动失败：无法获取 reader.exe 的程序路径。");
    return false;
  }

  std::wstring command_line = L"\"";
  command_line.append(executable);
  command_line.append(L"\"");

  // Keep all original switches and right-click file paths.
  const std::wstring original = GetCommandLineW();
  const wchar_t* p = original.c_str();
  bool inside_quotes = false;
  while (*p != L'\0') {
    if (*p == L'\"') inside_quotes = !inside_quotes;
    if (!inside_quotes && (*p == L' ' || *p == L'\t')) break;
    ++p;
  }
  while (*p == L' ' || *p == L'\t') ++p;
  if (*p != L'\0') {
    command_line.append(L" ");
    command_line.append(p);
  }
  command_line.append(L" --enable-software-rendering --disable-impeller");

  std::vector<wchar_t> mutable_command(command_line.begin(),
                                        command_line.end());
  mutable_command.push_back(L'\0');

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};

  const BOOL started = CreateProcessW(
      executable,
      mutable_command.data(),
      nullptr,
      nullptr,
      FALSE,
      CREATE_NO_WINDOW,
      nullptr,
      nullptr,
      &startup,
      &process);

  if (!started) {
    wchar_t details[512] = {};
    swprintf_s(details, _countof(details),
               L"无法启动软件渲染兼容进程。Windows 错误代码: %lu",
               static_cast<unsigned long>(GetLastError()));
    reader_crash::LogError(details);
    return false;
  }

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return false;  // caller exits; child continues.
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  reader_crash::InstallHandlers();
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // Flutter 3.16.9 uses the Skia renderer on Windows. This compatibility
  // build targets Windows 7 through Windows 11 and older GPU hardware.
  // Do not enable the newer Windows Impeller path.
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
                 SEM_NOOPENFILEERRORBOX);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  if (HasCommandLineSwitch(command_line_arguments,
                         "--native-crash-log-self-test")) {
    RaiseException(0xE0425244, EXCEPTION_NONCONTINUABLE, 0, nullptr);
    TerminateProcess(GetCurrentProcess(), 0xE0425244);
    return EXIT_FAILURE;
  }

  bool utility_mode = false;
  for (const auto& arg : command_line_arguments) {
    if (arg == "--tts-self-test" ||
        arg == "--crash-log-self-test" ||
        arg == "--native-crash-log-self-test" ||
        arg == "--install-context-menu" ||
        arg == "--uninstall-context-menu") {
      utility_mode = true;
      break;
    }
  }

  if (!utility_mode) {
    // 老 Windows / 基本显示适配器自动切到 Skia 软件渲染。
    // 子进程会保留原始右键文件路径和其他启动参数。
    if (!RelaunchWithSoftwareRenderingIfNeeded(command_line_arguments)) {
      return EXIT_SUCCESS;
    }

    // 正常应用进程建立运行标记；CI/右键注册自检不会留下异常退出标记。
    reader_crash::MarkStartup();
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Reader 阅读器", origin, size)) {
    reader_crash::LogError(L"FlutterWindow 创建失败，Reader 无法创建主窗口。");
    if (!utility_mode) {
      reader_crash::MarkCleanExit();
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (!utility_mode) {
    reader_crash::MarkCleanExit();
  }
  return EXIT_SUCCESS;
}
