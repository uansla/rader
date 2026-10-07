#include "crash_logger.h"

#include <windows.h>

#include <strsafe.h>

namespace reader_crash {
namespace {

constexpr wchar_t kProductDir[] = L"Reader";
constexpr wchar_t kLogName[] = L"Reader-Crash.log";

bool GetLogPath(wchar_t* out, size_t capacity) {
  wchar_t local_app_data[MAX_PATH] = {};
  DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data, static_cast<DWORD>(_countof(local_app_data)));
  if (length == 0 || length >= _countof(local_app_data)) {
    return false;
  }

  if (FAILED(StringCchPrintfW(out, capacity, L"%s\\%s\\%s",
                              local_app_data, kProductDir, kLogName))) {
    return false;
  }

  wchar_t dir[MAX_PATH] = {};
  if (FAILED(StringCchPrintfW(dir, _countof(dir), L"%s\\%s",
                              local_app_data, kProductDir))) {
    return false;
  }

  CreateDirectoryW(dir, nullptr);
  return true;
}

void WriteText(const wchar_t* text) {
  wchar_t path[MAX_PATH] = {};
  if (!GetLogPath(path, _countof(path))) {
    return;
  }

  HANDLE file = CreateFileW(
      path,
      FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  int utf8_length = WideCharToMultiByte(
      CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (utf8_length <= 1) {
    CloseHandle(file);
    return;
  }

  char buffer[2048] = {};
  int written_length = WideCharToMultiByte(
      CP_UTF8, 0, text, -1, buffer, sizeof(buffer), nullptr, nullptr);
  if (written_length > 1) {
    DWORD written = 0;
    WriteFile(file, buffer, static_cast<DWORD>(written_length - 1),
              &written, nullptr);
  }
  CloseHandle(file);
}

void LogError(const wchar_t* message) {
  SYSTEMTIME now = {};
  GetLocalTime(&now);
  wchar_t entry[2048] = {};
  StringCchPrintfW(
      entry, _countof(entry),
      L"===== Reader Windows 原生错误 =====\r\n"
      L"时间: %04u-%02u-%02u %02u:%02u:%02u.%03u\r\n"
      L"错误: %s\r\n\r\n",
      now.wYear, now.wMonth, now.wDay,
      now.wHour, now.wMinute, now.wSecond, now.wMilliseconds,
      message ? message : L"Unknown native error");
  WriteText(entry);
}
LONG WINAPI UnhandledExceptionFilter(EXCEPTION_POINTERS* exception) {
  wchar_t entry[2048] = {};
  const DWORD code = exception && exception->ExceptionRecord
      ? exception->ExceptionRecord->ExceptionCode
      : 0;
  const ULONG_PTR address = exception && exception->ExceptionRecord
      ? reinterpret_cast<ULONG_PTR>(exception->ExceptionRecord->ExceptionAddress)
      : 0;

  SYSTEMTIME now = {};
  GetLocalTime(&now);

  StringCchPrintfW(
      entry, _countof(entry),
      L"===== Reader Windows 原生崩溃 =====\r\n"
      L"时间: %04u-%02u-%02u %02u:%02u:%02u.%03u\r\n"
      L"异常代码: 0x%08lX\r\n"
      L"异常地址: 0x%p\r\n\r\n",
      now.wYear, now.wMonth, now.wDay,
      now.wHour, now.wMinute, now.wSecond, now.wMilliseconds,
      static_cast<unsigned long>(code),
      reinterpret_cast<void*>(address));

  WriteText(entry);
  return EXCEPTION_EXECUTE_HANDLER;
}

}  // namespace

void InstallHandlers() {
  SetUnhandledExceptionFilter(UnhandledExceptionFilter);
}

}  // namespace reader_crash
