#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <utility>
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

bool IsUtilityMode(const std::vector<std::string>& args) {
  return HasCommandLineSwitch(args, "--native-crash-log-self-test") ||
         HasCommandLineSwitch(args, "--crash-log-self-test") ||
         HasCommandLineSwitch(args, "--tts-self-test") ||
         HasCommandLineSwitch(args, "--install-context-menu") ||
         HasCommandLineSwitch(args, "--uninstall-context-menu");
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  reader_crash::InstallHandlers();

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // CI self-test: deliberately trigger an unhandled Windows exception to
  // verify that the native crash logger writes the diagnostic before exit.
  if (HasCommandLineSwitch(command_line_arguments,
                           "--native-crash-log-self-test")) {
    RaiseException(0xE0425244, EXCEPTION_NONCONTINUABLE, 0, nullptr);
    TerminateProcess(GetCurrentProcess(), 0xE0425244);
    return EXIT_FAILURE;
  }

  const bool utility_mode = IsUtilityMode(command_line_arguments);
  if (!utility_mode) {
    // A marker is removed only after a clean exit. If this process later
    // disappears unexpectedly, the next launch records a crash diagnostic.
    reader_crash::MarkStartup();
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // Keep the known working Skia renderer for this release.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Reader 阅读器", origin, size)) {
    reader_crash::LogError(L"FlutterWindow 创建失败，Reader 无法创建主窗口。");
    if (!utility_mode) {
      reader_crash::MarkCleanExit();
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  int message_result = 0;
  while ((message_result = ::GetMessage(&msg, nullptr, 0, 0)) > 0) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (message_result == -1) {
    reader_crash::LogError(L"Windows 消息循环 GetMessage 返回错误。");
  }

  ::CoUninitialize();
  if (!utility_mode) {
    reader_crash::MarkCleanExit();
  }
  return message_result == -1 ? EXIT_FAILURE : EXIT_SUCCESS;
}
