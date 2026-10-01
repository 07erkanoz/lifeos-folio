#include "rich_clipboard.h"

#include <cstring>
#include <initializer_list>

namespace {

gchar* ReadTarget(GtkClipboard* clipboard, const char* name) {
  const GdkAtom atom = gdk_atom_intern(name, FALSE);
  GtkSelectionData* selection =
      gtk_clipboard_wait_for_contents(clipboard, atom);
  if (selection == nullptr) return nullptr;

  const gint length = gtk_selection_data_get_length(selection);
  const guchar* bytes = gtk_selection_data_get_data(selection);
  gchar* result = nullptr;
  if (bytes != nullptr && length > 0) {
    if (g_utf8_validate(reinterpret_cast<const gchar*>(bytes), length,
                        nullptr)) {
      result = g_strndup(reinterpret_cast<const gchar*>(bytes), length);
    } else {
      // A few Wine/Windows clipboard owners publish HTML Format as UTF-16LE.
      result = g_convert(reinterpret_cast<const gchar*>(bytes), length,
                         "UTF-8", "UTF-16LE", nullptr, nullptr, nullptr);
    }
  }
  gtk_selection_data_free(selection);
  return result;
}

// Keep binary UYAP/RTF data intact; decoding it as UTF-8 destroys the stream.
FlValue* ReadRichData(GtkClipboard* clipboard) {
  GdkAtom* targets = nullptr;
  gint count = 0;
  if (!gtk_clipboard_wait_for_targets(clipboard, &targets, &count)) {
    return fl_value_new_null();
  }
  g_autoptr(FlValue) candidates = fl_value_new_list();
  size_t total_bytes = 0;
  // Prefer UYAP's own representation, then interoperable HTML and RTF.
  for (int priority = 0; priority < 3; ++priority) {
    for (gint i = 0; i < count; ++i) {
      g_autofree gchar* name = gdk_atom_name(targets[i]);
      const bool uyap = name != nullptr &&
          std::strstr(name, "application/x-java-serialized-object") != nullptr &&
          std::strstr(name, "EditorDataFlavor") != nullptr;
      const bool html = name != nullptr &&
          (g_str_has_prefix(name, "text/html") || std::strcmp(name, "HTML Format") == 0);
      const bool rtf = name != nullptr &&
          (g_str_has_prefix(name, "text/rtf") || g_str_has_prefix(name, "application/rtf") ||
           std::strcmp(name, "Rich Text Format") == 0 || std::strcmp(name, "text/richtext") == 0);
      if (!((priority == 0 && uyap) || (priority == 1 && html) || (priority == 2 && rtf))) continue;
      GtkSelectionData* selection = gtk_clipboard_wait_for_contents(clipboard, targets[i]);
      if (selection == nullptr) continue;
      const gint length = gtk_selection_data_get_length(selection);
      const guchar* bytes = gtk_selection_data_get_data(selection);
      if (bytes == nullptr || length <= 0 ||
          total_bytes + length > 32 * 1024 * 1024 ||
          fl_value_get_length(candidates) >= 8) {
        gtk_selection_data_free(selection);
        continue;
      }
      FlValue* result = fl_value_new_map();
      fl_value_set_string_take(result, "format", fl_value_new_string(uyap ? "uyap" : html ? "html" : "rtf"));
      fl_value_set_string_take(result, "data", fl_value_new_uint8_list(bytes, length));
      fl_value_set_string_take(result, "mime", fl_value_new_string(name));
      total_bytes += length;
      fl_value_append_take(candidates, result);
      gtk_selection_data_free(selection);
    }
  }
  g_free(targets);
  if (fl_value_get_length(candidates) == 0) return fl_value_new_null();
  // Preserve the original response fields for older callers, but keep the
  // other representations available if a decoder rejects the preferred one.
  FlValue* first = fl_value_get_list_value(candidates, 0);
  FlValue* result = fl_value_new_map();
  for (const char* key : {"format", "data", "mime"}) {
    fl_value_set_string(result, key, fl_value_lookup_string(first, key));
  }
  fl_value_set_string(result, "candidates", candidates);
  return result;
}

// What Folio copied, kept until another program takes the clipboard.
struct RichPayload {
  GBytes* text;
  GBytes* html;
  GBytes* rtf;
};

enum RichTarget : guint { kText = 1, kHtml, kRtf };

GBytes* BytesOf(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) return nullptr;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_UINT8_LIST) {
    return g_bytes_new(fl_value_get_uint8_list(value),
                       fl_value_get_length(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    const gchar* text = fl_value_get_string(value);
    return g_bytes_new(text, std::strlen(text));
  }
  return nullptr;
}

void FreePayload(RichPayload* payload) {
  if (payload == nullptr) return;
  if (payload->text != nullptr) g_bytes_unref(payload->text);
  if (payload->html != nullptr) g_bytes_unref(payload->html);
  if (payload->rtf != nullptr) g_bytes_unref(payload->rtf);
  g_free(payload);
}

void ProvidePayload(GtkClipboard*, GtkSelectionData* selection, guint info,
                    gpointer data) {
  auto* payload = static_cast<RichPayload*>(data);
  GBytes* bytes = info == kHtml  ? payload->html
                  : info == kRtf ? payload->rtf
                                 : payload->text;
  if (bytes == nullptr) return;
  gsize size = 0;
  const auto* raw = static_cast<const guchar*>(g_bytes_get_data(bytes, &size));
  if (info == kText) {
    // GTK converts to whichever text target was asked for.
    gtk_selection_data_set_text(selection, reinterpret_cast<const gchar*>(raw),
                                static_cast<gint>(size));
  } else {
    gtk_selection_data_set(selection, gtk_selection_data_get_target(selection),
                           8, raw, static_cast<gint>(size));
  }
}

void ClearPayload(GtkClipboard*, gpointer data) {
  FreePayload(static_cast<RichPayload*>(data));
}

// Offers HTML and RTF beside the text, as Word and LibreOffice do, so that
// what is copied in Folio keeps its fonts and layout wherever it is pasted.
bool WriteRichData(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return false;
  }
  auto* payload = g_new0(RichPayload, 1);
  payload->text = BytesOf(args, "text");
  payload->html = BytesOf(args, "html");
  payload->rtf = BytesOf(args, "rtf");
  GtkTargetList* list = gtk_target_list_new(nullptr, 0);
  if (payload->html != nullptr) {
    gtk_target_list_add(list, gdk_atom_intern_static_string("text/html"), 0,
                        kHtml);
  }
  if (payload->rtf != nullptr) {
    gtk_target_list_add(list, gdk_atom_intern_static_string("text/rtf"), 0,
                        kRtf);
    gtk_target_list_add(list, gdk_atom_intern_static_string("application/rtf"),
                        0, kRtf);
  }
  if (payload->text != nullptr) gtk_target_list_add_text_targets(list, kText);
  gint count = 0;
  GtkTargetEntry* targets = gtk_target_table_new_from_list(list, &count);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  const gboolean owned = gtk_clipboard_set_with_data(
      clipboard, targets, static_cast<guint>(count), ProvidePayload,
      ClearPayload, payload);
  if (owned) {
    // Lets a clipboard manager keep it once Folio closes.
    gtk_clipboard_set_can_store(clipboard, nullptr, 0);
  } else {
    FreePayload(payload);
  }
  gtk_target_table_free(targets, count);
  gtk_target_list_unref(list);
  return owned;
}

void Handle(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (std::strcmp(fl_method_call_get_name(call), "setRichData") == 0) {
    if (WriteRichData(fl_method_call_get_args(call))) {
      fl_method_call_respond_success(call, nullptr, nullptr);
    } else {
      fl_method_call_respond_error(call, "clipboard_write",
                                   "Clipboard could not be taken.", nullptr,
                                   nullptr);
    }
    return;
  }
  if (std::strcmp(fl_method_call_get_name(call), "getRichData") == 0) {
    g_autoptr(FlValue) value = ReadRichData(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
    fl_method_call_respond_success(call, value, nullptr);
    return;
  }
  if (std::strcmp(fl_method_call_get_name(call), "getHtml") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }

  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  g_autofree gchar* html = ReadTarget(clipboard, "text/html");
  if (html == nullptr) {
    html = ReadTarget(clipboard, "text/html;charset=utf-8");
  }
  if (html == nullptr) html = ReadTarget(clipboard, "HTML Format");

  g_autoptr(FlValue) value =
      html == nullptr ? fl_value_new_null() : fl_value_new_string(html);
  fl_method_call_respond_success(call, value, nullptr);
}

}  // namespace

void register_rich_clipboard(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "lifeos_evrak/rich_clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, Handle, nullptr, nullptr);
}
