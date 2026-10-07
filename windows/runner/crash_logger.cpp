#include "crash_logger.h"

#include <windows.h>

#include <cstdlib>
#include <cwchar>

#include <strsafe.h>

namespace reader_crash {
namespace {

constexpr wchar_t kProductDir[] = L"Reader";
constexpr wchar_t kLogName[] = L"Reader-Crash.log";
constexpr wchar_t kMarkerPrefix[] = L"Reader.running.";
constexpr DWORD kMaxLogBytes = 5 * 1024 * 1024;
DWORD g_process_id = 0;

bool GetProductDirectory(wchar_t* out, size_t capacity) {
  wchar_t local_app_data[MAX_PATH] = {};
  DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data,
      static_cast<DWORD>(_countof(local_app_data)));
  if (length == 0 || length >= _countof(local_app_data)) {
    return false;
  }

  if (FAILED(StringCchPrintfW(out, capacity, L"%s\\%s",
                              local_app_data, kProductDir))) {
    return false;
  }
  CreateDirectoryW(out, nullptr);
  return true;
}

bool GetLogPath(wchar_t* out, size_t capacity) {
  wchar_t dir[MAX_PATH] = {};
  if (!GetProductDirectory(dir, _countof(dir))) {
    return false;
  }
  return SUCCEEDED(StringCchPrintfW(
      out, capacity, L"%s\\%s", dir, kLogName));
}

bool GetMarkerPath(DWORD pid, wchar_t* out, size_t capacity) {
  wchar_t dir[MAX_PATH] = {};
  if (!GetProductDirectory(dir, _countof(dir))) {
    return false;
  }
  return SUCCEEDED(StringCchPrintfW(
      out, capacity, L"%s\\%s%lu", dir, kMarkerPrefix,
      static_cast<unsigned long>(pid)));
}

void WriteText(const wchar_t* text) {
  wchar_t path[MAX_PATH] = {};
  if (!GetLogPath(path, _countof(path))) {
    return;
  }

  HANDLE file = CreateFileW(
      path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  LARGE_INTEGER size = {};
  if (GetFileSizeEx(file, &size) && size.QuadPart > kMaxLogBytes) {
    SetFilePointer(file, 0, nullptr, FILE_BEGIN);
    SetEndOfFile(file);
  }

  const int utf8_length = WideCharToMultiByte(
      CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (utf8_length <= 1) {
    CloseHandle(file);
    return;
  }

  char* buffer = static_cast<char*>(malloc(static_cast<size_t>(utf8_length)));
  if (buffer == nullptr) {
    CloseHandle(file);
    return;
  }

  const int written_length = WideCharToMultiByte(
      CP_UTF8, 0, text, -1, buffer, utf8_length, nullptr, nullptr);
  if (written_length > 1) {
    DWORD written = 0;
    WriteFile(file, buffer, static_cast<DWORD>(written_length - 1),
              &written, nullptr);
  }

  free(buffer);
  CloseHandle(file);
}

void AppendStack(wchar_t* output, size_t capacity) {
  void* frames[8] = {};
  const USHORT count =
      CaptureStackBackTrace(1, static_cast<DWORD>(_countof(frames)), frames,
                            nullptr);
  StringCchCatW(output, capacity, L"调用地址:");
  for (USHORT i = 0; i < count; ++i) {
    wchar_t address[64] = {};
    StringCchPrintfW(address, _countof(address), L" 0x%p", frames[i]);
    StringCchCatW(output, capacity, address);
  }
  StringCchCatW(output, capacity, L"\r\n");
}

void WriteCrashDetails(const wchar_t* title, const wchar_t* details) {
  SYSTEMTIME now = {};
  GetLocalTime(&now);

  wchar_t entry[4096] = {};
  StringCchPrintfW(
      entry, _countof(entry),
      L"===== Reader 原生错误 =====\r\n"
      L"时间: %04u-%02u-%02u %02u:%02u:%02u.%03u\r\n"
      L"类型: %s\r\n"
      L"详情: %s\r\n",
      now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
      now.wSecond, now.wMilliseconds,
      title ? title : L"Unknown",
      details ? details : L"Unknown");
  AppendStack(entry, _countof(entry));
  StringCchCatW(entry, _countof(entry), L"\r\n");
  WriteText(entry);
}

bool IsProcessRunning(DWORD pid) {
  if (pid == 0 || pid == GetCurrentProcessId()) {
    return pid == GetCurrentProcessId();
  }

  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    // 权限不足时不误报。
    return GetLastError() == ERROR_ACCESS_DENIED;
  }

  DWORD exit_code = 0;
  const BOOL ok = GetExitCodeProcess(process, &exit_code);
  CloseHandle(process);
  return ok && exit_code == STILL_ACTIVE;
}

void RemoveStaleMarkers() {
  wchar_t dir[MAX_PATH] = {};
  if (!GetProductDirectory(dir, _countof(dir))) {
    return;
  }

  wchar_t pattern[MAX_PATH] = {};
  if (FAILED(StringCchPrintfW(
          pattern, _countof(pattern), L"%s\\%s*", dir, kMarkerPrefix))) {
    return;
  }

  WIN32_FIND_DATAW data = {};
  HANDLE finder = FindFirstFileW(pattern, &data);
  if (finder == INVALID_HANDLE_VALUE) {
    return;
  }

  do {
    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      continue;
    }

    const size_t prefix_length = _countof(kMarkerPrefix) - 1;
    if (wcsncmp(data.cFileName, kMarkerPrefix, prefix_length) != 0) {
      continue;
    }

    wchar_t* end = nullptr;
    const unsigned long pid_value =
        wcstoul(data.cFileName + prefix_length, &end, 10);
    if (end == data.cFileName + prefix_length ||
        *end != L'\0' || pid_value == 0) {
      continue;
    }

    const DWORD pid = static_cast<DWORD>(pid_value);
    if (pid == GetCurrentProcessId() || IsProcessRunning(pid)) {
      continue;
    }

    wchar_t marker_path[MAX_PATH] = {};
    if (SUCCEEDED(StringCchPrintfW(
            marker_path, _countof(marker_path), L"%s\\%s", dir,
            data.cFileName))) {
      wchar_t details[512] = {};
      StringCchPrintfW(
          details, _countof(details),
          L"检测到进程 PID %lu 上次未正常退出，可能发生闪退或被强制结束。",
          static_cast<unsigned long>(pid));
      WriteCrashDetails(L"上次异常退出", details);
      DeleteFileW(marker_path);
    }
  } while (FindNextFileW(finder, &data));

  FindClose(finder);
}

void CreateCurrentMarker() {
  const DWORD pid = GetCurrentProcessId();
  g_process_id = pid;

  wchar_t path[MAX_PATH] = {};
  if (!GetMarkerPath(pid, path, _countof(path))) {
    return;
  }

  HANDLE file = CreateFileW(
      path, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
      FILE_ATTRIBUTE_HIDDEN, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    CloseHandle(file);
  }
}

LONG WINAPI UnhandledExceptionFilter(EXCEPTION_POINTERS* exception) {
  const DWORD code = exception && exception->ExceptionRecord
      ? exception->ExceptionRecord->ExceptionCode
      : 0;

  wchar_t details[1024] = {};
  StringCchPrintfW(
      details, _countof(details),
      L"异常代码: 0x%08lX  异常地址: 0x%p",
      static_cast<unsigned long>(code),
      exception && exception->ExceptionRecord
          ? exception->ExceptionRecord->ExceptionAddress
          : nullptr);
  WriteCrashDetails(L"Windows 未处理异常 / 闪退", details);

  return EXCEPTION_EXECUTE_HANDLER;
}

}  // namespace

void LogError(const wchar_t* message) {
  WriteCrashDetails(L"明确错误", message);
}

void InstallHandlers() {
  SetUnhandledExceptionFilter(UnhandledExceptionFilter);
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
               SEM_NOOPENFILEERRORBOX);
}

void MarkStartup() {
  RemoveStaleMarkers();
  CreateCurrentMarker();
}

void MarkCleanExit() {
  if (g_process_id == 0) {
    return;
  }

  wchar_t path[MAX_PATH] = {};
  if (GetMarkerPath(g_process_id, path, _countof(path))) {
    DeleteFileW(path);
  }
  g_process_id = 0;
}

}  // namespace reader_crash
