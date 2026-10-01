#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <memory>

class FileActions {
 public:
  FileActions(flutter::BinaryMessenger* messenger, HWND window);
  ~FileActions();
 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::ApplicationModel::DataTransfer::DataTransferManager share_manager_{nullptr};
  winrt::event_token share_token_{};
  bool share_registered_ = false;
  void Share(const std::wstring& path);
};
