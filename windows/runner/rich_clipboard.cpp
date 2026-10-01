#include "rich_clipboard.h"
#include "rich_clipboard_data.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <string>
#include <vector>

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

struct ClipboardLock {
  ~ClipboardLock() { CloseClipboard(); }
};

template <typename T>
T Lookup(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return T();
  const auto* value = std::get_if<T>(&it->second);
  return value ? *value : T();
}

EncodableValue ReadRichData() {
  EncodableList candidates;
  for (auto& item : folio::ReadRichClipboardData()) {
    candidates.emplace_back(EncodableMap{
        {EncodableValue("format"), EncodableValue(std::move(item.format))},
        {EncodableValue("data"), EncodableValue(std::move(item.data))},
    });
  }
  if (candidates.empty()) return EncodableValue();
  return EncodableValue(EncodableMap{
      {EncodableValue("candidates"), EncodableValue(std::move(candidates))},
  });
}
}  // namespace

RichClipboard::RichClipboard(flutter::BinaryMessenger* messenger, HWND window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "lifeos_evrak/rich_clipboard",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() == "setRichData") {
      const auto* args = std::get_if<EncodableMap>(call.arguments());
      if (!args) {
        result->Error("bad_args", "Clipboard data is missing.");
        return;
      }
      if (!OpenClipboard(window)) {
        result->Error("clipboard_busy", "Clipboard is temporarily in use.");
        return;
      }
      ClipboardLock lock;
      if (folio::WriteRichClipboardData(
              Lookup<std::string>(*args, "text"),
              Lookup<std::vector<uint8_t>>(*args, "html"),
              Lookup<std::vector<uint8_t>>(*args, "rtf"))) {
        result->Success();
      } else {
        result->Error("clipboard_write", "Clipboard could not be written.");
      }
      return;
    }
    if (call.method_name() != "getRichData") {
      result->NotImplemented();
      return;
    }
    if (!OpenClipboard(window)) {
      result->Error("clipboard_busy", "Clipboard is temporarily in use.");
      return;
    }
    ClipboardLock lock;
    result->Success(ReadRichData());
  });
}

RichClipboard::~RichClipboard() { channel_->SetMethodCallHandler(nullptr); }
