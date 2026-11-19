#ifndef RUNNER_EGL_CONFIG_FIX_H_
#define RUNNER_EGL_CONFIG_FIX_H_

// Lets GTK find an OpenGL config on Wayland where Mesa offers no OpenGL
// ES 1 config (Mesa 26.3.1): called once, before GTK starts.
void fix_egl_config_choice();

#endif  // RUNNER_EGL_CONFIG_FIX_H_
