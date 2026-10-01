// Run under a private X server (xvfb-run), never against the user's clipboard.
#include "../../linux/runner/rich_clipboard.cc"
#include <fstream>
#include <iterator>
#include <vector>
#include <cassert>

struct Selection {
  std::vector<guchar> bytes;
  const char* mime;
};
void Supply(GtkClipboard*, GtkSelectionData* data, guint, gpointer user_data) {
  auto* selection = static_cast<Selection*>(user_data);
  gtk_selection_data_set(data, gdk_atom_intern(selection->mime, FALSE), 8,
                         selection->bytes.data(), selection->bytes.size());
}
void Check(GtkClipboard* clipboard, Selection* selection, const char* expected) {
  GtkTargetEntry target{const_cast<gchar*>(selection->mime), 0, 0};
  assert(gtk_clipboard_set_with_data(clipboard, &target, 1, Supply, nullptr, selection));
  g_autoptr(FlValue) result = ReadRichData(clipboard);
  assert(fl_value_get_type(result) == FL_VALUE_TYPE_MAP);
  assert(std::strcmp(fl_value_get_string(fl_value_lookup_string(result, "format")), expected) == 0);
  FlValue* bytes = fl_value_lookup_string(result, "data");
  assert(fl_value_get_length(bytes) == selection->bytes.size());
  assert(std::memcmp(fl_value_get_uint8_list(bytes), selection->bytes.data(), selection->bytes.size()) == 0);
  gtk_clipboard_clear(clipboard);
}
int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  assert(argc == 2);
  std::ifstream input(argv[1], std::ios::binary);
  Selection uyap{{std::istreambuf_iterator<char>(input), {}},
    "JAVA_DATAFLAVOR:application/x-java-serialized-object; class=tr.com.havelsan.uyap.system.editor.common.text.EditorDataFlavor"};
  assert(!uyap.bytes.empty());
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  Check(clipboard, &uyap, "uyap");
  Selection html{{'<','b','>','x','<','/','b','>'}, "text/html;charset=UTF-8"};
  Check(clipboard, &html, "html");
  Selection rtf{{'{','\\','r','t','f','1',' ','x','}'}, "application/rtf"};
  Check(clipboard, &rtf, "rtf");
  g_print("GTK clipboard: UYAP, HTML charset target and RTF bytes preserved.\n");
}
