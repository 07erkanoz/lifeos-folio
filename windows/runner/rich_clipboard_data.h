#pragma once
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace folio {
struct ClipboardRepresentation {
  std::string format;
  std::vector<uint8_t> data;
};
// Caller owns an OpenClipboard lock for the duration of this read.
inline std::vector<ClipboardRepresentation> ReadRichClipboardData() {
  std::vector<ClipboardRepresentation> candidates;
  size_t total_bytes = 0;
  // Word publishes CF_HTML and Rich Text Format alongside CF_UNICODETEXT.
  // Keep bytes intact: CF_HTML offsets count UTF-8 bytes, RTF has its own
  // encoding, and UYAP's serialized payload is binary.
  for (int priority = 0; priority < 3; ++priority) {
    for (UINT id = EnumClipboardFormats(0); id != 0;
         id = EnumClipboardFormats(id)) {
      char buffer[1024] = {};
      const int length = GetClipboardFormatNameA(id, buffer, 1024);
      if (length <= 0) continue;
      const std::string name(buffer, static_cast<size_t>(length));
      const bool uyap = name.find("application/x-java-serialized-object") != std::string::npos &&
                        name.find("EditorDataFlavor") != std::string::npos;
      const bool html = name == "HTML Format" || name.find("text/html") == 0;
      const bool rtf = name == "Rich Text Format" || name == "text/rtf" ||
                       name == "application/rtf";
      if (!((priority == 0 && uyap) || (priority == 1 && html) ||
            (priority == 2 && rtf))) continue;
      const HANDLE handle = GetClipboardData(id);
      if (!handle) continue;
      const SIZE_T size = GlobalSize(handle);
      if (size == 0 || size > 32 * 1024 * 1024 - total_bytes ||
          candidates.size() >= 8) continue;
      const auto* bytes = static_cast<const uint8_t*>(GlobalLock(handle));
      if (!bytes) continue;
      std::vector<uint8_t> data(bytes, bytes + size);
      GlobalUnlock(handle);
      total_bytes += size;
      candidates.push_back({uyap ? "uyap" : html ? "html" : "rtf", std::move(data)});
    }
  }
  return candidates;
}

inline std::wstring WideFromUtf8(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), length);
  return wide;
}

inline bool PutClipboardBytes(UINT format, const void* data, size_t size) {
  const HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!handle) return false;
  void* memory = GlobalLock(handle);
  if (!memory) {
    GlobalFree(handle);
    return false;
  }
  std::memcpy(memory, data, size);
  GlobalUnlock(handle);
  // The clipboard owns the memory once it has taken it, and only then.
  if (!SetClipboardData(format, handle)) {
    GlobalFree(handle);
    return false;
  }
  return true;
}

// Caller owns an OpenClipboard lock. Folio's copy, the way Word publishes
// its own: Unicode text beside CF_HTML and Rich Text Format, so each program
// takes the richest one it reads. [html] is CF_HTML with its header already
// in place; both it and [rtf] get the terminating NUL readers expect.
inline bool WriteRichClipboardData(const std::string& text,
                                   const std::vector<uint8_t>& html,
                                   const std::vector<uint8_t>& rtf) {
  if (!EmptyClipboard()) return false;
  const std::wstring wide = WideFromUtf8(text);
  bool written = PutClipboardBytes(CF_UNICODETEXT, wide.c_str(),
                                   (wide.size() + 1) * sizeof(wchar_t));
  const auto put = [&written](const wchar_t* name,
                              const std::vector<uint8_t>& bytes) {
    if (bytes.empty()) return;
    std::vector<uint8_t> terminated(bytes);
    terminated.push_back(0);
    written = PutClipboardBytes(RegisterClipboardFormatW(name),
                                terminated.data(), terminated.size()) &&
              written;
  };
  put(L"HTML Format", html);
  put(L"Rich Text Format", rtf);
  return written;
}
}  // namespace folio
