#include "file_actions.h"
#include <cstring>

static void respond(FlMethodCall* call, const gchar* error = nullptr) {
  if (error) fl_method_call_respond_error(call, "FILE_ACTION", error, nullptr, nullptr);
  else fl_method_call_respond_success(call, nullptr, nullptr);
}

static gboolean is_self(GAppInfo* app) {
  const gchar* id = g_app_info_get_id(app);
  const gchar* executable = g_app_info_get_executable(app);
  g_autofree gchar* name = executable ? g_path_get_basename(executable) : nullptr;
  return g_strcmp0(id, "lifeos-evrakci.desktop") == 0 ||
      g_strcmp0(id, "com.erkanoz.evrak_convert.desktop") == 0 ||
      g_strcmp0(name, "evrak_convert") == 0 ||
      g_strcmp0(name, "lifeos_folio") == 0;
}

struct Choice { FlMethodCall* call; GFile* file; };
static void choice_response(GtkDialog* dialog, gint response, gpointer data) {
  auto* choice = static_cast<Choice*>(data);
  g_autoptr(GError) error = nullptr;
  if (response == GTK_RESPONSE_OK) {
    g_autoptr(GAppInfo) app = gtk_app_chooser_get_app_info(GTK_APP_CHOOSER(dialog));
    if (app && is_self(app)) {
      respond(choice->call, "Belge zaten LifeOS Folio’da açık. Başka bir uygulama seçin.");
    } else if (app) {
      GList files = {choice->file, nullptr, nullptr};
      g_autoptr(GdkAppLaunchContext) context = gdk_display_get_app_launch_context(gtk_widget_get_display(GTK_WIDGET(dialog)));
      g_app_info_launch(app, &files, G_APP_LAUNCH_CONTEXT(context), &error);
      respond(choice->call, error ? error->message : nullptr);
    } else respond(choice->call);
  } else respond(choice->call);
  gtk_widget_destroy(GTK_WIDGET(dialog));
  g_object_unref(choice->call);
  g_object_unref(choice->file);
  delete choice;
}

static void choose_app(GtkWindow* window, FlMethodCall* call, GFile* file) {
  GtkWidget* dialog = gtk_app_chooser_dialog_new(window, GTK_DIALOG_MODAL, file);
  gtk_window_set_title(GTK_WINDOW(dialog), "Birlikte aç");
  gtk_app_chooser_dialog_set_heading(GTK_APP_CHOOSER_DIALOG(dialog), "Belgeyi açacak uygulamayı seçin");
  auto* choice = new Choice{FL_METHOD_CALL(g_object_ref(call)), G_FILE(g_object_ref(file))};
  g_signal_connect(dialog, "response", G_CALLBACK(choice_response), choice);
  gtk_widget_show(dialog);
}

struct ClipboardFile { gchar* uri; gchar* path; };
static void clipboard_get(GtkClipboard*, GtkSelectionData* selection, guint info, gpointer data) {
  auto* file = static_cast<ClipboardFile*>(data);
  g_autofree gchar* text = info == 0 ? g_strconcat("copy\n", file->uri, nullptr) :
      info == 1 ? g_strconcat(file->uri, "\r\n", nullptr) :
      info == 2 ? g_strdup("0") : g_strdup(file->path);
  gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8,
      reinterpret_cast<const guchar*>(text), static_cast<gint>(strlen(text)));
}
static void clipboard_clear(GtkClipboard*, gpointer data) {
  auto* file = static_cast<ClipboardFile*>(data);
  g_free(file->uri); g_free(file->path); delete file;
}

static void handle(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* window = GTK_WINDOW(data);
  FlValue* args = fl_method_call_get_args(call);
  FlValue* path_value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "path") : nullptr;
  if (!path_value || fl_value_get_type(path_value) != FL_VALUE_TYPE_STRING) {
    respond(call, "Belge yolu eksik."); return;
  }
  const gchar* path = fl_value_get_string(path_value);
  if (!g_path_is_absolute(path) || !g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
    respond(call, "Belge bulunamadı."); return;
  }
  const gchar* action = fl_method_call_get_name(call);
  g_autoptr(GFile) file = g_file_new_for_path(path);
  g_autoptr(GError) error = nullptr;
  if (strcmp(action, "openWith") == 0) {
    choose_app(window, call, file); return;
  }
  if (strcmp(action, "openDefault") == 0) {
    g_autoptr(GAppInfo) app = g_file_query_default_handler(file, nullptr, &error);
    if (!app || is_self(app)) { choose_app(window, call, file); return; }
    GList files = {file, nullptr, nullptr};
    g_autoptr(GdkAppLaunchContext) context = gdk_display_get_app_launch_context(gtk_widget_get_display(GTK_WIDGET(window)));
    g_app_info_launch(app, &files, G_APP_LAUNCH_CONTEXT(context), &error);
    respond(call, error ? error->message : nullptr); return;
  }
  if (strcmp(action, "copyFile") == 0) {
    GtkTargetEntry targets[] = {
      {const_cast<gchar*>("x-special/gnome-copied-files"), 0, 0},
      {const_cast<gchar*>("text/uri-list"), 0, 1},
      {const_cast<gchar*>("application/x-kde-cutselection"), 0, 2},
      {const_cast<gchar*>("UTF8_STRING"), 0, 3},
    };
    auto* payload = new ClipboardFile{g_file_get_uri(file), g_strdup(path)};
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    if (!gtk_clipboard_set_with_data(clipboard, targets, G_N_ELEMENTS(targets), clipboard_get, clipboard_clear, payload)) {
      clipboard_clear(clipboard, payload); respond(call, "Dosya panoya kopyalanamadı."); return;
    }
    gtk_clipboard_set_can_store(clipboard, nullptr, 0);
    respond(call); return;
  }
  if (strcmp(action, "showFolder") == 0) {
    g_autoptr(GFile) parent = g_file_get_parent(file);
    g_autofree gchar* uri = g_file_get_uri(parent);
    g_app_info_launch_default_for_uri(uri, nullptr, &error);
    respond(call, error ? error->message : nullptr); return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

void register_file_actions(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "lifeos_evrak/file_actions", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle, g_object_ref(window), g_object_unref);
}
