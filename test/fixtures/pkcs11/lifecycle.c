// Offline PKCS#11 double. No PC/SC calls and no real card or PIN access.
#include <stdio.h>
#include <stddef.h>
typedef unsigned long U;
static void record(const char *event) {
  FILE *file = fopen(LOG_PATH, "a");
  if (file) { fprintf(file, "%s\n", event); fclose(file); }
}
__attribute__((constructor)) static void loaded(void) { record("load"); }
__attribute__((destructor)) static void unloaded(void) { record("unload"); }
static U initialize(void *args) { record("initialize"); return MODE == 1 ? 5 : MODE == 3 ? 0x191 : 0; }
static U finalize(void *args) { record("finalize"); return MODE == 4 ? 5 : 0; }
static U open_session(U slot, U flags, void *app, void *notify, U *handle) { record("open"); *handle = 7; return 0; }
static U close_session(U handle) { record("close"); return MODE == 4 ? 5 : 0; }
static U login(U handle, U kind, unsigned char *pin, U length) { record("login"); return MODE == 2 ? 0xA0 : 0; }
static U logout(U handle) { record("logout"); return MODE == 4 ? 5 : 0; }
static struct { unsigned char version[2]; void *functions[68]; } functions = {
  {2, 40}, {[0] = initialize, [1] = finalize, [12] = open_session, [13] = close_session, [18] = login, [19] = logout}
};
#if MODE != 5
U C_GetFunctionList(void **out) { *out = &functions; return 0; }
#endif
