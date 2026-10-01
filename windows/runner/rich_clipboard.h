#pragma once

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class RichClipboard {
 public:
  RichClipboard(flutter::BinaryMessenger* messenger, HWND window);
  ~RichClipboard();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
