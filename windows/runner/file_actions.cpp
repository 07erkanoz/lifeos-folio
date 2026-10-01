#include "file_actions.h"
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <cstring>
#include <vector>

using namespace winrt::Windows::ApplicationModel::DataTransfer;
using namespace winrt::Windows::Storage;

// Deferral keeps the share request alive while Windows resolves the file;
// the document bytes are never read into Flutter memory.
static winrt::fire_and_forget ProvideFile(DataRequest request, std::wstring path) {
  auto deferral = request.GetDeferral();
  try {
    auto file = co_await StorageFile::GetFileFromPathAsync(path);
    request.Data().Properties().Title(file.Name());
    request.Data().RequestedOperation(DataPackageOperation::Copy);
    auto items = winrt::single_threaded_vector<IStorageItem>();
    items.Append(file);
    request.Data().SetStorageItems(items, true);
  } catch (...) {
    request.FailWithDisplayText(L"Belge paylaşıma hazırlanamadı. Dosyayı kopyalayarak paylaşabilirsiniz.");
  }
  deferral.Complete();
}

void FileActions::Share(const std::wstring& path) {
  auto interop = winrt::get_activation_factory<DataTransferManager, IDataTransferManagerInterop>();
  if (!share_manager_) {
    winrt::check_hresult(interop->GetForWindow(window_, winrt::guid_of<DataTransferManager>(), winrt::put_abi(share_manager_)));
  }
  if (share_registered_) share_manager_.DataRequested(share_token_);
  share_token_ = share_manager_.DataRequested([path](const DataTransferManager&, const DataRequestedEventArgs& args) {
    ProvideFile(args.Request(), path);
  });
  share_registered_ = true;
  winrt::check_hresult(interop->ShowShareUIForWindow(window_));
}

static bool IsOwnDefault(const std::wstring& path) {
  DWORD size = 0;
  AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_EXECUTABLE, PathFindExtensionW(path.c_str()), L"open", nullptr, &size);
  if (size == 0) return false;
  std::vector<wchar_t> app(size);
  if (FAILED(AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_EXECUTABLE, PathFindExtensionW(path.c_str()), L"open", app.data(), &size))) return false;
  wchar_t own[32768]{};
  GetModuleFileNameW(nullptr, own, 32768);
  return _wcsicmp(app.data(), own) == 0 ||
      _wcsicmp(PathFindFileNameW(app.data()), PathFindFileNameW(own)) == 0;
}

static void CopyFileToClipboard(HWND window, const std::wstring& path) {
  const SIZE_T length = (path.size() + 2) * sizeof(wchar_t);
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(DROPFILES) + length);
  if (!memory) winrt::throw_last_error();
  auto* drop = static_cast<DROPFILES*>(GlobalLock(memory));
  if (!drop) { GlobalFree(memory); winrt::throw_last_error(); }
  drop->pFiles = sizeof(DROPFILES);
  drop->fWide = TRUE;
  std::memcpy(reinterpret_cast<BYTE*>(drop) + sizeof(DROPFILES), path.c_str(), (path.size() + 1) * sizeof(wchar_t));
  GlobalUnlock(memory);
  if (!OpenClipboard(window)) { GlobalFree(memory); winrt::throw_last_error(); }
  EmptyClipboard();
  if (!SetClipboardData(CF_HDROP, memory)) {
    CloseClipboard(); GlobalFree(memory); winrt::throw_last_error();
  }
  // Explicit copy effect prevents a receiving file manager from moving the source.
  HGLOBAL effect = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (effect) {
    auto* value = static_cast<DWORD*>(GlobalLock(effect));
    if (value) {
      *value = DROPEFFECT_COPY;
      GlobalUnlock(effect);
      if (!SetClipboardData(RegisterClipboardFormatW(L"Preferred DropEffect"), effect)) GlobalFree(effect);
    } else GlobalFree(effect);
  }
  CloseClipboard();
}

FileActions::FileActions(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lifeos_evrak/file_actions", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    try {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) { result->Error("FILE_ACTION", "Belge yolu eksik."); return; }
      auto entry = args->find(flutter::EncodableValue("path"));
      if (entry == args->end() || !std::holds_alternative<std::string>(entry->second)) {
        result->Error("FILE_ACTION", "Belge yolu eksik."); return;
      }
      const std::wstring path(winrt::to_hstring(std::get<std::string>(entry->second)));
      DWORD attrs = GetFileAttributesW(path.c_str());
      if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        result->Error("FILE_ACTION", "Belge bulunamadı."); return;
      }
      const auto& action = call.method_name();
      if (action == "openWith" || (action == "openDefault" && IsOwnDefault(path))) {
        OPENASINFO info{path.c_str(), nullptr, OAIF_EXEC};
        HRESULT hr = SHOpenWithDialog(window_, &info);
        if (hr != HRESULT_FROM_WIN32(ERROR_CANCELLED)) winrt::check_hresult(hr);
      } else if (action == "openDefault") {
        auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(window_, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
        if (status <= 32) { result->Error("FILE_ACTION", "Belge açılamadı. Birlikte aç seçeneğini deneyin."); return; }
      } else if (action == "share") {
        Share(path);
      } else if (action == "copyFile") {
        CopyFileToClipboard(window_, path);
      } else if (action == "showFolder") {
        PIDLIST_ABSOLUTE item = ILCreateFromPathW(path.c_str());
        if (!item) { result->Error("FILE_ACTION", "Klasör bulunamadı."); return; }
        HRESULT hr = SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
        ILFree(item);
        winrt::check_hresult(hr);
      } else { result->NotImplemented(); return; }
      result->Success();
    } catch (const winrt::hresult_error& error) {
      result->Error("FILE_ACTION", winrt::to_string(error.message()));
    } catch (...) {
      result->Error("FILE_ACTION", "Belge işlemi tamamlanamadı.");
    }
  });
}

FileActions::~FileActions() {
  channel_->SetMethodCallHandler(nullptr);
  try {
    if (share_registered_) share_manager_.DataRequested(share_token_);
  } catch (...) {}
}
