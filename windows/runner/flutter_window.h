#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "file_actions.h"
#include "quick_search.h"
#include "spell_check.h"
#include "rich_clipboard.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Releases the engine and the view, after marking the window as shutting
  // down. Called from OnDestroy and from the destructor, whichever comes first.
  void ReleaseFlutter();

  // Set before the controller is released. A unique_ptr keeps its stored
  // pointer while the deleter runs, so during teardown flutter_controller_
  // still reads as non-null even though the engine behind it is gone.
  bool shutting_down_ = false;

  std::unique_ptr<FileActions> file_actions_;
  std::unique_ptr<QuickSearch> quick_search_;
  std::unique_ptr<SpellCheck> spell_check_;
  std::unique_ptr<RichClipboard> rich_clipboard_;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
