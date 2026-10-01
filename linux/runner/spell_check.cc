#include "spell_check.h"

#include <dlfcn.h>
#include <glib.h>

#include <cstring>

#include <string>
#include <vector>

namespace {

// Enchant's C interface, reached through dlopen so nothing has to be
// installed to build this.
struct Enchant {
  void* library = nullptr;
  void* broker = nullptr;
  void* dict = nullptr;
  bool tried = false;

  void* (*broker_init)() = nullptr;
  void (*broker_free)(void*) = nullptr;
  void* (*request_dict)(void*, const char*) = nullptr;
  void (*free_dict)(void*, void*) = nullptr;
  int (*dict_exists)(void*, const char*) = nullptr;
  int (*dict_check)(void*, const char*, ssize_t) = nullptr;
  char** (*dict_suggest)(void*, const char*, ssize_t, size_t*) = nullptr;
  void (*free_string_list)(void*, char**) = nullptr;
  void (*dict_add)(void*, const char*, ssize_t) = nullptr;
};

Enchant& Bridge() {
  static Enchant bridge;
  return bridge;
}

template <typename T>
bool Bind(void* library, const char* name, T* slot) {
  *slot = reinterpret_cast<T>(dlsym(library, name));
  return *slot != nullptr;
}

// Distributions disagree on the tag, and on which one they ship.
const char* const kTags[] = {"tr_TR", "tr", "tr-TR"};

bool Ready() {
  Enchant& e = Bridge();
  if (e.dict != nullptr) return true;
  if (e.tried) return false;
  e.tried = true;

  for (const char* name :
       {"libenchant-2.so.2", "libenchant-2.so", "libenchant.so.1"}) {
    e.library = dlopen(name, RTLD_LAZY | RTLD_LOCAL);
    if (e.library != nullptr) break;
  }
  if (e.library == nullptr) return false;

  if (!Bind(e.library, "enchant_broker_init", &e.broker_init) ||
      !Bind(e.library, "enchant_broker_free", &e.broker_free) ||
      !Bind(e.library, "enchant_broker_request_dict", &e.request_dict) ||
      !Bind(e.library, "enchant_broker_free_dict", &e.free_dict) ||
      !Bind(e.library, "enchant_broker_dict_exists", &e.dict_exists) ||
      !Bind(e.library, "enchant_dict_check", &e.dict_check) ||
      !Bind(e.library, "enchant_dict_suggest", &e.dict_suggest) ||
      !Bind(e.library, "enchant_dict_free_string_list", &e.free_string_list) ||
      !Bind(e.library, "enchant_dict_add", &e.dict_add)) {
    return false;
  }

  e.broker = e.broker_init();
  if (e.broker == nullptr) return false;
  for (const char* tag : kTags) {
    if (e.dict_exists(e.broker, tag) == 0) continue;
    e.dict = e.request_dict(e.broker, tag);
    if (e.dict != nullptr) return true;
  }
  return false;
}

// A word, and where it sits counted the way Dart counts: in UTF-16 code
// units. Enchant is handed the UTF-8, so the two have to be tracked apart.
struct Word {
  std::string text;
  int64_t start = 0;
  int64_t length = 0;
};

// The same stretch with the curly apostrophe written straight.
//
// Word and LibreOffice turn ' into ’ as it is typed, so anything arriving
// from a .docx is full of them, and Turkish puts one in nearly every proper
// noun that carries a suffix. Hunspell's Turkish knows only the straight
// one: Ankara'da it accepts, Ankara’da it does not. Both are a single
// UTF-16 unit, so swapping them leaves every offset where it was.
std::string Straighten(const char* from, const char* to) {
  std::string out;
  out.reserve(static_cast<size_t>(to - from));
  for (const char* at = from; at < to;) {
    const gunichar c = g_utf8_get_char(at);
    const char* next = g_utf8_next_char(at);
    if (c == 0x2019) {
      out.push_back('\'');
    } else {
      out.append(at, static_cast<size_t>(next - at));
    }
    at = next;
  }
  return out;
}

std::vector<Word> WordsIn(const char* text) {
  std::vector<Word> words;
  if (text == nullptr || !g_utf8_validate(text, -1, nullptr)) return words;

  int64_t utf16 = 0;
  const char* at = text;
  const char* word_start = nullptr;
  int64_t word_utf16 = 0;
  bool has_letter = false;
  bool has_digit = false;

  auto close = [&](const char* end) {
    if (word_start == nullptr) return;
    // A run with a figure in it is nothing anyone can spell: 2025'te,
    // 13'üncü and A4 are all ordinary writing and the checker has no
    // opinion about them worth drawing.
    if (has_letter && !has_digit) {
      words.push_back(
          Word{Straighten(word_start, end), word_utf16, utf16 - word_utf16});
    }
    word_start = nullptr;
  };

  while (*at != '\0') {
    const gunichar c = g_utf8_get_char(at);
    const bool alpha = g_unichar_isalpha(c);
    const bool digit = g_unichar_isdigit(c);
    // An apostrophe inside a word belongs to it: Ankara'da is one word, and
    // Turkish writes a great many of its proper nouns that way. Figures are
    // kept for the same reason, so 2025'te stays one run and is passed over
    // whole rather than leaving a bare te behind to be underlined.
    const bool part = alpha || digit ||
                      ((c == '\'' || c == 0x2019) && word_start != nullptr);
    if (part) {
      if (word_start == nullptr) {
        word_start = at;
        word_utf16 = utf16;
        has_letter = false;
        has_digit = false;
      }
      if (alpha) has_letter = true;
      if (digit) has_digit = true;
    } else {
      close(at);
    }
    utf16 += c >= 0x10000 ? 2 : 1;
    at = g_utf8_next_char(at);
  }
  close(at);

  // A trailing apostrophe was not part of a word after all. Straighten has
  // already made the curly one straight, so there is a single form to cut.
  for (Word& word : words) {
    while (!word.text.empty() && word.text.back() == '\'') {
      word.text.pop_back();
      word.length -= 1;
    }
  }
  return words;
}

gchar* StringArgument(FlValue* args, const char* name) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, name);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return g_strdup(fl_value_get_string(value));
}

// A word handed over from Dart, straightened and checked for sense.
//
// The editor takes the word out of the document as it stands, so it still
// carries whatever apostrophe was typed there; the dictionary has to be
// asked in the one form it knows.
std::string WordArgument(FlValue* args) {
  g_autofree gchar* given = StringArgument(args, "word");
  if (given == nullptr || !g_utf8_validate(given, -1, nullptr)) return {};
  return Straighten(given, given + strlen(given));
}

void Respond(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}

void Handle(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (g_strcmp0(name, "available") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(Ready());
    Respond(call, value);
    return;
  }
  if (!Ready()) {
    // Not an error: a machine without Turkish spelling underlines nothing.
    g_autoptr(FlValue) value = fl_value_new_null();
    Respond(call, value);
    return;
  }
  Enchant& e = Bridge();

  if (g_strcmp0(name, "check") == 0) {
    g_autofree gchar* text = StringArgument(args, "text");
    g_autoptr(FlValue) found = fl_value_new_list();
    for (const Word& word : WordsIn(text)) {
      if (word.text.empty()) continue;
      // Enchant answers zero for a word it knows and a negative for a
      // question it could not answer; only a positive means wrong.
      if (e.dict_check(e.dict, word.text.c_str(),
                       static_cast<ssize_t>(word.text.size())) <= 0) {
        continue;
      }
      g_autoptr(FlValue) entry = fl_value_new_map();
      fl_value_set_string_take(entry, "start", fl_value_new_int(word.start));
      fl_value_set_string_take(entry, "length", fl_value_new_int(word.length));
      fl_value_set_string_take(entry, "repeated", fl_value_new_bool(FALSE));
      fl_value_append(found, entry);
    }
    Respond(call, found);
    return;
  }
  if (g_strcmp0(name, "suggest") == 0) {
    const std::string word = WordArgument(args);
    g_autoptr(FlValue) out = fl_value_new_list();
    if (!word.empty()) {
      size_t count = 0;
      char** given = e.dict_suggest(e.dict, word.c_str(),
                                    static_cast<ssize_t>(word.size()), &count);
      if (given != nullptr) {
        for (size_t i = 0; i < count && i < 8; i++) {
          if (given[i] != nullptr) {
            fl_value_append_take(out, fl_value_new_string(given[i]));
          }
        }
        e.free_string_list(e.dict, given);
      }
    }
    Respond(call, out);
    return;
  }
  if (g_strcmp0(name, "add") == 0) {
    const std::string word = WordArgument(args);
    if (!word.empty()) {
      e.dict_add(e.dict, word.c_str(), static_cast<ssize_t>(word.size()));
    }
    g_autoptr(FlValue) value = fl_value_new_null();
    Respond(call, value);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void register_spell_check(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "folio/spellcheck", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, Handle, nullptr, nullptr);
}
