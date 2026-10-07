#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "crash_logger.h"
#include "flutter_window.h"
#include "utils.h"

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
  // Flutter 3.18.x uses the Skia renderer on Windows. This compatibility
  // build targets Windows 7 through Windows 11 and older GPU hardware.
  // Do not enable the newer Windows Impeller path.
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
                 SEM_NOOPENFILEERRORBOX);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  bool utility_mode = false;
  for (const auto& arg : command_line_arguments) {
    if (arg == "--tts-self-test" ||
        arg == "--crash-log-self-test" ||
        arg == "--install-context-menu" ||
        arg == "--uninstall-context-menu") {
      utility_mode = true;
      break;
    }
  }

  if (!utility_mode) {
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
