#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { ReleaseFlutter(); }

bool FlutterWindow::OnCreate() {
  // Win32Window::Create tears down any previous window before it builds this
  // one, and that teardown runs OnDestroy, which raises the shutting-down flag
  // even on the very first call when there is nothing to destroy. Left raised,
  // MessageHandler returns before it ever reaches Flutter, so no plugin sees a
  // window message for the whole life of the app: the caption stays visible
  // because window_manager never gets WM_NCCALCSIZE, the minimum size is not
  // enforced, and focus, move and resize events never fire. Lower it here,
  // where a window is about to exist again.
  shutting_down_ = false;
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  file_actions_ = std::make_unique<FileActions>(flutter_controller_->engine()->messenger(), GetHandle());
  quick_search_ = std::make_unique<QuickSearch>(flutter_controller_->engine()->messenger(), GetHandle());
  spell_check_ = std::make_unique<SpellCheck>(flutter_controller_->engine()->messenger());
  rich_clipboard_ = std::make_unique<RichClipboard>(flutter_controller_->engine()->messenger(), GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Dart shows the window after configuring the custom chrome and saved bounds.
  // Showing it on the first frame races window_manager's title-bar setup.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ReleaseFlutter() {
  // Destroying the view destroys its child window, and Windows reports that to
  // this window as WM_PARENTNOTIFY while the engine is already gone. The flag
  // is raised first so MessageHandler stops forwarding before that happens.
  shutting_down_ = true;
  rich_clipboard_.reset();
  spell_check_.reset();
  quick_search_.reset();
  file_actions_.reset();
  flutter_controller_ = nullptr;
}

void FlutterWindow::OnDestroy() {
  ReleaseFlutter();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (shutting_down_) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
  if (quick_search_ && quick_search_->Handle(message, wparam)) return 0;
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
