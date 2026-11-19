#include "egl_config_fix.h"

#include <dlfcn.h>
#include <stdint.h>

#include <vector>

// EGL's own types and the few names used, without its headers.
namespace {
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef void* EGLDisplay;
typedef void* EGLConfig;
constexpr EGLint kNone = 0x3038;
constexpr EGLint kRenderableType = 0x3040;
constexpr EGLint kOpenGLBit = 0x0008;
constexpr EGLint kOpenGLES2Bit = 0x0004;

using Choose = EGLBoolean (*)(EGLDisplay, const EGLint*, EGLConfig*, EGLint,
                              EGLint*);
Choose real_choose = nullptr;

// GTK 3 asks EGL for a config on Wayland without EGL_RENDERABLE_TYPE, which
// then means OpenGL ES 1 by the EGL rules. Mesa 26.3.1 (Arch, 19 Kasım
// 2026) offers no ES 1 config, GTK found none and every GTK OpenGL window,
// Folio's among them, stayed black (GNOME/gtk#8566, mesa#16934). When
// such a question finds nothing, it is asked again for desktop OpenGL and
// ES 2, as GTK means it; any other question is passed on as asked.
EGLBoolean choose_config(EGLDisplay display, const EGLint* attributes,
                         EGLConfig* configs, EGLint size, EGLint* count) {
  EGLBoolean ok = real_choose(display, attributes, configs, size, count);
  if (!ok || count == nullptr || *count > 0) return ok;
  std::vector<EGLint> asked;
  for (const EGLint* a = attributes; a != nullptr && *a != kNone; a += 2) {
    if (a[0] == kRenderableType) return ok;
    asked.push_back(a[0]);
    asked.push_back(a[1]);
  }
  asked.push_back(kRenderableType);
  asked.push_back(kOpenGLBit | kOpenGLES2Bit);
  asked.push_back(kNone);
  return real_choose(display, asked.data(), configs, size, count);
}
}  // namespace

void fix_egl_config_choice() {
  // GTK calls EGL through libepoxy's function pointers: the one for
  // eglChooseConfig is pointed at the wrapper, before GTK makes a context.
  auto* slot =
      reinterpret_cast<Choose*>(dlsym(RTLD_DEFAULT, "epoxy_eglChooseConfig"));
  if (slot == nullptr) return;
  void* egl = dlopen("libEGL.so.1", RTLD_LAZY | RTLD_LOCAL);
  if (egl == nullptr) return;
  real_choose = reinterpret_cast<Choose>(dlsym(egl, "eglChooseConfig"));
  if (real_choose == nullptr) return;
  *slot = choose_config;
}
