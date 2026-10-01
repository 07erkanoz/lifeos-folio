#include <flutter_linux/flutter_linux.h>
#include <gdk/gdkx.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#include <X11/Xlib.h>
#include <X11/keysym.h>

struct QuickSearch {
  FlMethodChannel* channel;
  GtkWindow* window;
  Display* display = nullptr;
  gchar* exported_handle = nullptr;
  GdkWindow* exported_window = nullptr;
  unsigned int key = 0, modifiers = 0;
};
static const unsigned int locks[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
static GdkFilterReturn hotkey_event(GdkXEvent* raw, GdkEvent*, gpointer data) {
  auto* state = static_cast<QuickSearch*>(data);
  auto* event = static_cast<XEvent*>(raw);
  if (event->type == KeyPress && event->xkey.keycode == state->key &&
      (event->xkey.state & ~(LockMask | Mod2Mask)) == state->modifiers) {
    fl_method_channel_invoke_method(state->channel, "activated", nullptr, nullptr, nullptr, nullptr);
    return GDK_FILTER_REMOVE;
  }
  return GDK_FILTER_CONTINUE;
}
static void release_key(QuickSearch* state) {
  if (!state->display || !state->key) return;
  for (auto lock : locks) XUngrabKey(state->display, state->key, state->modifiers | lock, DefaultRootWindow(state->display));
  XFlush(state->display);
  state->key = 0;
}
static void quick_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<QuickSearch*>(data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "unregister") == 0) {
    release_key(state);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "parentWindow") == 0) {
    GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(state->window));
    if (window && GDK_IS_X11_WINDOW(window)) {
      g_autofree gchar* parent = g_strdup_printf("x11:%lx", gdk_x11_window_get_xid(window));
      g_autoptr(FlValue) value = fl_value_new_string(parent);
      fl_method_call_respond_success(call, value, nullptr);
    }
#ifdef GDK_WINDOWING_WAYLAND
    else if (window && GDK_IS_WAYLAND_WINDOW(window)) {
      if (state->exported_handle) {
        g_autoptr(FlValue) value = fl_value_new_string(state->exported_handle);
        fl_method_call_respond_success(call, value, nullptr);
        return;
      }
      state->exported_window = GDK_WINDOW(g_object_ref(window));
      // GTK owns the export until the window is released.
      struct ExportRequest { FlMethodCall* call; QuickSearch* state; };
      auto* pending = new ExportRequest{FL_METHOD_CALL(g_object_ref(call)), state};
      if (!gdk_wayland_window_export_handle(window,
          [](GdkWindow*, const char* handle, gpointer data) {
            g_autofree gchar* parent = g_strdup_printf("wayland:%s", handle);
            auto* request = static_cast<ExportRequest*>(data);
            request->state->exported_handle = g_strdup(parent);
            g_autoptr(FlValue) value = fl_value_new_string(parent);
            fl_method_call_respond_success(request->call, value, nullptr);
          }, pending, [](gpointer data) {
            auto* request = static_cast<ExportRequest*>(data);
            g_object_unref(request->call);
            delete request;
          })) {
        g_object_unref(pending->call);
        delete pending;
        g_clear_object(&state->exported_window);
        g_autoptr(FlValue) value = fl_value_new_string("");
        fl_method_call_respond_success(call, value, nullptr);
      }
    }
#endif
    else {
      g_autoptr(FlValue) value = fl_value_new_string("");
      fl_method_call_respond_success(call, value, nullptr);
    }
  } else if (g_strcmp0(method, "activate") == 0) {
    auto* value = fl_method_call_get_args(call);
    if (value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING && *fl_value_get_string(value))
      gtk_window_set_startup_id(state->window, fl_value_get_string(value));
    gtk_window_present(state->window);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "register") == 0) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(state->window));
    if (!GDK_IS_X11_DISPLAY(display)) {
      fl_method_call_respond_error(call, "WAYLAND", "Wayland kısayolu masaüstü portalı üzerinden ayarlanmalı.", nullptr, nullptr);
      return;
    }
    release_key(state);
    state->display = gdk_x11_display_get_xdisplay(display);
    FlValue* args = fl_method_call_get_args(call);
    auto* key = fl_value_lookup_string(args, "key");
    auto* mods = fl_value_lookup_string(args, "modifiers");
    if (!key || !mods) { fl_method_call_respond_error(call, "KEY", "Kısayol geçersiz.", nullptr, nullptr); return; }
    unsigned int bits = fl_value_get_int(mods);
    state->modifiers = ((bits & 1) ? ControlMask : 0) | ((bits & 2) ? Mod1Mask : 0) |
                       ((bits & 4) ? ShiftMask : 0) | ((bits & 8) ? Mod4Mask : 0);
    state->key = XKeysymToKeycode(state->display, XStringToKeysym(fl_value_get_string(key)));
    if (!state->key) { fl_method_call_respond_error(call, "KEY", "Kısayol tuşu desteklenmiyor.", nullptr, nullptr); return; }
    gdk_x11_display_error_trap_push(display);
    for (auto lock : locks) XGrabKey(state->display, state->key, state->modifiers | lock,
        DefaultRootWindow(state->display), False, GrabModeAsync, GrabModeAsync);
    XSync(state->display, False);
    const int error = gdk_x11_display_error_trap_pop(display);
    if (error) {
      release_key(state);
      fl_method_call_respond_error(call, "CONFLICT", "Bu kısayol başka bir uygulama tarafından kullanılıyor.", nullptr, nullptr);
    } else fl_method_call_respond_success(call, nullptr, nullptr);
  } else fl_method_call_respond_not_implemented(call, nullptr);
}
static void quick_destroy(gpointer data) {
  auto* state = static_cast<QuickSearch*>(data);
  release_key(state);
  gdk_window_remove_filter(nullptr, hotkey_event, state);
  g_object_unref(state->channel);
#ifdef GDK_WINDOWING_WAYLAND
  if (state->exported_window) gdk_wayland_window_unexport_handle(state->exported_window);
#endif
  g_clear_object(&state->exported_window);
  g_free(state->exported_handle);
  delete state;
}
void register_quick_search(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.erkanoz.folio/quick_search", FL_METHOD_CODEC(codec));
  auto* state = new QuickSearch{channel, window};
  fl_method_channel_set_method_call_handler(channel, quick_call, state, nullptr);
  gdk_window_add_filter(nullptr, hotkey_event, state);
  g_object_set_data_full(G_OBJECT(view), "folio-quick-search", state, quick_destroy);
}
