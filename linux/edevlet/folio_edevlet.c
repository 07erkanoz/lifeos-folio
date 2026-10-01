// LifeOS Folio — e-Devlet ile UYAP girişi için tarayıcı penceresi (Linux).
//
// Flutter'ın Linux gömücüsünde platform görünümü yok; bir GTK/WebKit
// görünümü Flutter ağacına gömülemez. CEF bunu ekran dışı çizimle aşar ama
// yüzlerce megabaytlık bir kütüphane ister. Bu yüzden sistemin WebKitGTK'sı
// ayrı bir süreçte, ayrı bir pencerede çalışır: WebKit çökerse Folio
// etkilenmez, geçici bağlam sayesinde diske hiçbir çerez yazılmaz.
//
// Folio UYAP oturumunu kendisi açar ve e-Devlet sayfasının adresini verir.
// Kullanıcı e-Devlet'te mobil imza ya da e-imza ile onaylayınca e-Devlet
// UYAP'ın dönüş adresine yönlendirir; bu yönlendirme YÜKLENMEDEN durdurulur
// ve içindeki kod Folio'ya verilir. Kodu UYAP'a, oturumun sahibi olan Folio
// götürür; tarayıcı götürseydi oturumsuz bir istek kodu harcayabilirdi.
//
// Protokol (stdout):  kod=<oauth kodu>\n
// Çıkış kodları:  0 kod alındı | 2 kullanıcı vazgeçti | 64 hatalı parametre
//
// GÜVENLİK: dönüş adresi kodu taşır. Tam adres hiçbir günlüğe yazılmaz;
// kod yalnız stdout borusundan Folio'ya gider.
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>
#include <webkit2/webkit2.h>

typedef struct {
  const gchar *redirect;
  gboolean got;
  GtkWidget *window;
} State;

// gtk_main_quit() doğrudan çağrılmaz: yönlendirme gtk_main() başlamadan
// gelebilir; boşta kuyruğa alınca döngü başladığında güvenle kapanır.
static gboolean quit_now(gpointer data) {
  (void)data;
  gtk_main_quit();
  return G_SOURCE_REMOVE;
}

static gchar *code_of(const gchar *uri) {
  GUri *u = g_uri_parse(uri, G_URI_FLAGS_NONE, NULL);
  if (!u) return NULL;
  const gchar *query = g_uri_get_query(u);
  gchar *code = NULL;
  if (query) {
    GHashTable *params =
        g_uri_parse_params(query, -1, "&", G_URI_PARAMS_NONE, NULL);
    if (params) {
      const gchar *value = g_hash_table_lookup(params, "code");
      if (value && *value) code = g_strdup(value);
      g_hash_table_unref(params);
    }
  }
  g_uri_unref(u);
  return code;
}

// TRUE when [uri] is the return address and its code was handed over.
static gboolean take(State *s, const gchar *uri) {
  if (s->got || !uri || !g_str_has_prefix(uri, s->redirect)) return FALSE;
  gchar *code = code_of(uri);
  if (!code) return FALSE;
  s->got = TRUE;
  g_print("kod=%s\n", code);
  fflush(stdout);
  g_free(code);
  g_idle_add(quit_now, NULL);
  return TRUE;
}

// Every navigation, a server redirect included, is asked about first: the
// return address is stopped here, before its request leaves.
static gboolean decide(WebKitWebView *view, WebKitPolicyDecision *decision,
                       WebKitPolicyDecisionType type, gpointer data) {
  (void)view;
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }
  WebKitNavigationAction *action = webkit_navigation_policy_decision_get_navigation_action(
      WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  const gchar *uri =
      webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
  if (take(data, uri)) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  return FALSE;
}

// Should a version of WebKit not ask about a redirect, the address it lands
// on is caught all the same.
static void uri_changed(WebKitWebView *view, GParamSpec *spec, gpointer data) {
  (void)spec;
  if (take(data, webkit_web_view_get_uri(view))) {
    webkit_web_view_stop_loading(view);
  }
}

// e-Devlet's e-imza page opens its help in a new window; it goes to the
// system's browser rather than nowhere.
static GtkWidget *new_window(WebKitWebView *view,
                             WebKitNavigationAction *action, gpointer data) {
  (void)view;
  State *s = data;
  const gchar *uri =
      webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
  if (uri && !take(s, uri)) {
    gtk_show_uri_on_window(GTK_WINDOW(s->window), uri, GDK_CURRENT_TIME, NULL);
  }
  return NULL;
}

static void closed(GtkWidget *widget, gpointer data) {
  (void)widget;
  (void)data;
  g_idle_add(quit_now, NULL);
}

int main(int argc, char **argv) {
  gchar *url = NULL, *redirect = NULL, *hint = NULL;
  GOptionEntry options[] = {
      {"url", 0, 0, G_OPTION_ARG_STRING, &url, "e-Devlet adresi", "URL"},
      {"redirect", 0, 0, G_OPTION_ARG_STRING, &redirect,
       "Kodun döndüğü adresin başı", "ADRES"},
      {"hint", 0, 0, G_OPTION_ARG_STRING, &hint, "Pencerenin üstündeki not",
       "METİN"},
      {NULL, 0, 0, G_OPTION_ARG_NONE, NULL, NULL, NULL}};
  GOptionContext *context = g_option_context_new("- e-Devlet ile UYAP girişi");
  g_option_context_add_main_entries(context, options, NULL);
  g_option_context_add_group(context, gtk_get_option_group(TRUE));
  if (!g_option_context_parse(context, &argc, &argv, NULL) || !url || !*url ||
      !redirect || !*redirect) {
    g_printerr("folio-edevlet: --url ve --redirect gerekir.\n");
    return 64;
  }
  g_option_context_free(context);

  State state = {.redirect = redirect, .got = FALSE, .window = NULL};

  // Geçici bağlam: ortak bir bilgisayarda bir önceki kişinin e-Devlet
  // oturumu kalmaz; çerez ve önbellek diske hiç yazılmaz.
  WebKitWebContext *web = webkit_web_context_new_ephemeral();
  WebKitWebView *view = WEBKIT_WEB_VIEW(
      g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", web, NULL));

  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  state.window = window;
  gtk_window_set_title(GTK_WINDOW(window), "e-Devlet ile UYAP girişi");
  gtk_window_set_default_size(GTK_WINDOW(window), 560, 720);
  gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
  gtk_window_set_keep_above(GTK_WINDOW(window), TRUE);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  if (hint && *hint) {
    GtkWidget *label = gtk_label_new(hint);
    gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_widget_set_margin_start(label, 12);
    gtk_widget_set_margin_end(label, 12);
    gtk_widget_set_margin_top(label, 8);
    gtk_widget_set_margin_bottom(label, 8);
    gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
  }
  gtk_box_pack_start(GTK_BOX(box), GTK_WIDGET(view), TRUE, TRUE, 0);
  gtk_container_add(GTK_CONTAINER(window), box);

  g_signal_connect(view, "decide-policy", G_CALLBACK(decide), &state);
  g_signal_connect(view, "notify::uri", G_CALLBACK(uri_changed), &state);
  g_signal_connect(view, "create", G_CALLBACK(new_window), &state);
  g_signal_connect(window, "destroy", G_CALLBACK(closed), NULL);

  gtk_widget_show_all(window);
  webkit_web_view_load_uri(view, url);
  gtk_main();
  return state.got ? 0 : 2;
}
