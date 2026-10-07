#ifndef READER_CRASH_LOGGER_H_
#define READER_CRASH_LOGGER_H_

namespace reader_crash {

// 安装未处理的 Windows 原生异常记录。
// 正常启动、正常阅读、正常退出不会写错误日志。
void InstallHandlers();

// 记录明确的原生错误。
void LogError(const wchar_t* message);

// 用运行标记识别没有机会回调的异常退出。
void MarkStartup();
void MarkCleanExit();

}  // namespace reader_crash

#endif  // READER_CRASH_LOGGER_H_
