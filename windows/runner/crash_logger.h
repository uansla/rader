#ifndef READER_CRASH_LOGGER_H_
#define READER_CRASH_LOGGER_H_

namespace reader_crash {

// Installs a Windows unhandled-exception logger.
// It records only fatal native process exceptions; normal runtime events are
// never written to the crash log.
void InstallHandlers();
void LogError(const wchar_t* message);

}  // namespace reader_crash

#endif  // READER_CRASH_LOGGER_H_
