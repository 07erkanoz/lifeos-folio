#include "my_application.h"
#include <initializer_list>
#include "file_actions.h"
#include "spell_check.h"
#include "rich_clipboard.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"

void register_quick_search(FlView* view, GtkWindow* window);

#ifdef FOLIO_EDITOR
// LifeOS Editor: the same app, asked for its editor alone.
static constexpr const char* kTitle = "LifeOS Edit\xc3\xb6r";
static constexpr const char* kIcon = "lifeos_editor.png";
#else
static constexpr const char* kTitle = "LifeOS Folio";
static constexpr const char* kIcon = "lifeos_folio.png";
#endif

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// GTK asks a Wayland compositor to draw an undecorated window's frame
// (org_kde_kwin_server_decoration's SERVER mode); KWin does, and a second
// caption sat above Folio's own on KDE. Asked after GTK's own realize, the
// window draws its frame itself: Folio's caption, nothing above it. GNOME
// has no such protocol and is not changed. A window given its system
// frame back (a plain title bar asked for) asks the compositor for it.
static void own_decorations_cb(GtkWidget* window, gpointer) {
#ifdef GDK_WINDOWING_WAYLAND
  GdkWindow* gdk_window = gtk_widget_get_window(window);
  if (gdk_window == nullptr || !GDK_IS_WAYLAND_WINDOW(gdk_window)) return;
  if (gtk_window_get_decorated(GTK_WINDOW(window))) {
    gdk_wayland_window_announce_ssd(gdk_window);
  } else {
    gdk_wayland_window_announce_csd(gdk_window);
  }
#endif
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Folio draws its own caption. Do not create then hide a GTK header bar:
  // its CSD decoration/input regions can survive hiding on GNOME/Wayland.
  gtk_window_set_title(window, kTitle);
  gtk_window_set_decorated(window, FALSE);
  g_signal_connect_after(window, "realize", G_CALLBACK(own_decorations_cb),
                         nullptr);
  g_signal_connect_after(window, "notify::decorated",
                         G_CALLBACK(own_decorations_cb), nullptr);

  gtk_window_set_default_size(window, 1280, 720);
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon = g_build_filename(directory, "data", "flutter_assets",
        "assets", "branding", kIcon, nullptr);
    // X11 task bars consume _NET_WM_ICON; publish practical sizes instead of
    // a single large source image. Wayland resolves the matching desktop ID.
    gtk_window_set_default_icon_name(APPLICATION_ID);
    gtk_window_set_icon_name(window, APPLICATION_ID);
    g_autoptr(GdkPixbuf) source = gdk_pixbuf_new_from_file(icon, nullptr);
    if (source != nullptr) {
      GList* icons = nullptr;
      for (const int size : {32, 48, 64, 128, 256}) {
        GdkPixbuf* scaled = gdk_pixbuf_scale_simple(source, size, size,
                                                   GDK_INTERP_BILINEAR);
        if (scaled != nullptr) icons = g_list_append(icons, scaled);
      }
      gtk_window_set_default_icon_list(icons);
      gtk_window_set_icon_list(window, icons);
      g_list_free_full(icons, g_object_unref);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_file_actions(view, window);
  register_quick_search(view, window);
  register_spell_check(view);
  register_rich_clipboard(view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
#ifdef FOLIO_EDITOR
  // And put --editor first, which is all that makes this program the editor.
  {
    GStrvBuilder* builder = g_strv_builder_new();
    g_strv_builder_add(builder, "--editor");
    g_strv_builder_addv(builder, (const char**)(*arguments + 1));
    self->dart_entrypoint_arguments = g_strv_builder_end(builder);
    g_strv_builder_unref(builder);
  }
#else
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
#endif

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
