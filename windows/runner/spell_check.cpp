#include "spell_check.h"

#include <flutter/standard_method_codec.h>

#include <vector>

namespace {

std::wstring Widen(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                       static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      out.data(), size);
  return out;
}

std::string Narrow(const std::wstring& text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
                                       static_cast<int>(text.size()), nullptr, 0,
                                       nullptr, nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      out.data(), size, nullptr, nullptr);
  return out;
}

std::string Argument(const flutter::EncodableValue* arguments, const char* name) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return {};
  const auto found = map->find(flutter::EncodableValue(name));
  if (found == map->end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

}  // namespace

SpellCheck::SpellCheck(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "folio/spellcheck",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const std::string& name = call.method_name();
    const std::string language = Argument(call.arguments(), "language");

    if (name == "available") {
      result->Success(flutter::EncodableValue(Ready(language)));
      return;
    }
    if (!Ready(language)) {
      // Not an error: a machine without Turkish spelling is a machine that
      // simply does not underline anything.
      result->Success(flutter::EncodableValue());
      return;
    }
    if (name == "check") {
      const std::wstring text = Widen(Argument(call.arguments(), "text"));
      winrt::com_ptr<IEnumSpellingError> errors;
      if (FAILED(checker_->Check(text.c_str(), errors.put())) || !errors) {
        result->Success(flutter::EncodableValue(flutter::EncodableList{}));
        return;
      }
      flutter::EncodableList found;
      for (;;) {
        winrt::com_ptr<ISpellingError> error;
        if (errors->Next(error.put()) != S_OK || !error) break;
        ULONG start = 0, length = 0;
        CORRECTIVE_ACTION action = CORRECTIVE_ACTION_NONE;
        error->get_StartIndex(&start);
        error->get_Length(&length);
        error->get_CorrectiveAction(&action);
        if (length == 0) continue;
        // Both sides count in UTF-16 code units, so an index here is an
        // index in the Dart string as it stands, with nothing to convert.
        found.push_back(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("start"),
             flutter::EncodableValue(static_cast<int64_t>(start))},
            {flutter::EncodableValue("length"),
             flutter::EncodableValue(static_cast<int64_t>(length))},
            {flutter::EncodableValue("repeated"),
             flutter::EncodableValue(action == CORRECTIVE_ACTION_DELETE)},
        }));
      }
      result->Success(flutter::EncodableValue(found));
      return;
    }
    if (name == "suggest") {
      const std::wstring word = Widen(Argument(call.arguments(), "word"));
      winrt::com_ptr<IEnumString> suggestions;
      flutter::EncodableList out;
      if (SUCCEEDED(checker_->Suggest(word.c_str(), suggestions.put())) &&
          suggestions) {
        for (int i = 0; i < 8; i++) {
          LPOLESTR value = nullptr;
          if (suggestions->Next(1, &value, nullptr) != S_OK || !value) break;
          out.push_back(flutter::EncodableValue(Narrow(value)));
          CoTaskMemFree(value);
        }
      }
      result->Success(flutter::EncodableValue(out));
      return;
    }
    if (name == "add") {
      const std::wstring word = Widen(Argument(call.arguments(), "word"));
      // Into the reader's own dictionary, where every other Windows
      // program will see it too.
      checker_->Add(word.c_str());
      result->Success(flutter::EncodableValue());
      return;
    }
    result->NotImplemented();
  });
}

SpellCheck::~SpellCheck() = default;

bool SpellCheck::Ready(const std::string& language) {
  const std::wstring wanted = Widen(language.empty() ? "tr-TR" : language);
  if (checker_ && wanted == language_) return true;
  if (tried_ && wanted == language_) return false;
  language_ = wanted;
  tried_ = true;
  checker_ = nullptr;
  if (!factory_) {
    if (FAILED(CoCreateInstance(__uuidof(SpellCheckerFactory), nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(factory_.put())))) {
      return false;
    }
  }
  BOOL supported = FALSE;
  if (FAILED(factory_->IsSupported(wanted.c_str(), &supported)) || !supported) {
    return false;
  }
  return SUCCEEDED(
      factory_->CreateSpellChecker(wanted.c_str(), checker_.put()));
}
