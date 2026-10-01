#ifndef FOLIO_QUICK_SEARCH_H_
#define FOLIO_QUICK_SEARCH_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
class QuickSearch {
 public:
  QuickSearch(flutter::BinaryMessenger* messenger, HWND window);
  ~QuickSearch();
  bool Handle(UINT message, WPARAM wparam);
 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
