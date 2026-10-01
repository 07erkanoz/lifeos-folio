#include "quick_search.h"
#include <cctype>
constexpr int kFolioHotkey = 0x464F;
QuickSearch::QuickSearch(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger,
      "com.erkanoz.folio/quick_search", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "unregister") {
      UnregisterHotKey(window_, kFolioHotkey); result->Success();
    } else if (call.method_name() == "activate") {
      SetForegroundWindow(window_); result->Success();
    } else if (call.method_name() == "register") {
      UnregisterHotKey(window_, kFolioHotkey);
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) { result->Error("KEY", "Kısayol geçersiz."); return; }
      const auto key = args->find(flutter::EncodableValue("key"));
      const auto mods = args->find(flutter::EncodableValue("modifiers"));
      if (key == args->end() || mods == args->end()) { result->Error("KEY", "Kısayol geçersiz."); return; }
      const auto text = std::get<std::string>(key->second);
      const auto bits = std::get<int32_t>(mods->second);
      UINT vk = text == "space" ? VK_SPACE : 0;
      if (text.size() == 1) vk = static_cast<UINT>(toupper(text[0]));
      if (text.size() > 1 && text[0] == 'F') {
        try { const int n = std::stoi(text.substr(1)); if (n >= 1 && n <= 12) vk = VK_F1 + n - 1; } catch (...) {}
      }
      UINT flags = MOD_NOREPEAT | ((bits & 1) ? MOD_CONTROL : 0) | ((bits & 2) ? MOD_ALT : 0) |
                   ((bits & 4) ? MOD_SHIFT : 0) | ((bits & 8) ? MOD_WIN : 0);
      if (!vk || !RegisterHotKey(window_, kFolioHotkey, flags, vk))
        result->Error("CONFLICT", "Kısayol başka bir uygulama tarafından kullanılıyor veya kullanılamıyor.");
      else result->Success();
    } else result->NotImplemented();
  });
}
QuickSearch::~QuickSearch() { UnregisterHotKey(window_, kFolioHotkey); }
bool QuickSearch::Handle(UINT message, WPARAM wparam) {
  if (message != WM_HOTKEY || wparam != kFolioHotkey) return false;
  channel_->InvokeMethod("activated", nullptr);
  return true;
}
