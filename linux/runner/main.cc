#include <gtk/gtk.h>
#include <stdlib.h>
#include <unistd.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "egl_config_fix.h"
#include "my_application.h"

// Whether GTK can make an OpenGL context on this Wayland session, after
// fix_egl_config_choice: if a driver still gives it none, the window would
// stay black (as with Mesa 26.3.1, 19 Kasım 2026); through XWayland it
// draws.
static gboolean wayland_without_gl() {
#ifdef GDK_WINDOWING_WAYLAND
  if (!gtk_init_check(nullptr, nullptr)) return FALSE;
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_WAYLAND_DISPLAY(display)) return FALSE;
  GtkWidget* probe = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_widget_realize(probe);
  g_autoptr(GError) error = nullptr;
  GdkGLContext* context =
      gdk_window_create_gl_context(gtk_widget_get_window(probe), &error);
  gboolean failed = context == nullptr ||
                    !gdk_gl_context_realize(context, &error);
  if (failed) {
    g_warning("Wayland'da OpenGL bağlamı kurulamadı (%s); X11 ile açılıyor.",
              error != nullptr ? error->message : "?");
  }
  g_clear_object(&context);
  gtk_widget_destroy(probe);
  return failed;
#else
  return FALSE;
#endif
}

int main(int argc, char** argv) {
  fix_egl_config_choice();
  // Started again through X11 when Wayland gives GTK no OpenGL; never when
  // the backend was chosen already (by the person, or by this same check).
  if (g_getenv("GDK_BACKEND") == nullptr && g_getenv("DISPLAY") != nullptr &&
      wayland_without_gl()) {
    setenv("GDK_BACKEND", "x11", TRUE);
    g_autofree gchar* self = g_file_read_link("/proc/self/exe", nullptr);
    if (self != nullptr) execv(self, argv);
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
