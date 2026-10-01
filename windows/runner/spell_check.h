#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <spellcheck.h>
#include <winrt/base.h>

#include <memory>
#include <string>

// Turkish spelling, from the one place on a Windows machine that already
// knows Turkish.
//
// Shipping a word list of our own is no good for an agglutinative language:
// mahkemesine, dilekçesiyle and davalılardan are all ordinary words a list
// would have to hold a form of each, and it never holds enough. Windows has
// carried a real Turkish checker since 8, the reader has probably already
// taught it the names it uses, and it suggests corrections as well as
// finding faults. So this asks it rather than guessing.
class SpellCheck {
 public:
  SpellCheck(flutter::BinaryMessenger* messenger);
  ~SpellCheck();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::com_ptr<ISpellCheckerFactory> factory_;
  winrt::com_ptr<ISpellChecker> checker_;
  std::wstring language_;
  bool tried_ = false;

  // Made once and kept: building a checker reads the dictionaries off disk.
  bool Ready(const std::string& language);
};
