#pragma once
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>

// The most recent failure on this thread, readable from Dart through
// Native_lastError() after a constructor returns null. A native constructor
// must never exit() the process: the app has to be able to show the reason.
inline std::string &lastErrorRef() {
  static thread_local std::string message;
  return message;
}

inline void setLastError(const char *what) {
  char buf[256];
  snprintf(buf, sizeof(buf), "%s: %s", what, strerror(errno));
  lastErrorRef() = buf;
}
