cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
# Folio and LifeOS Editör are one app built twice: the editor's runner is
# compiled with FOLIO_EDITOR, which asks the Dart side for its editor alone
# and gives the program its own name, icon and taskbar identity. Both share
# the engine, the plugins and the data folder next to them.
function(folio_runner TARGET)
  add_executable(${TARGET} WIN32
    "flutter_window.cpp"
    "file_actions.cpp"
    "quick_search.cpp"
    "spell_check.cpp"
    "rich_clipboard.cpp"
    "main.cpp"
    "utils.cpp"
    "win32_window.cpp"
    "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
    "Runner.rc"
    "runner.exe.manifest"
  )

  # Apply the standard set of build settings. This can be removed for
  # applications that need different build settings.
  apply_standard_settings(${TARGET})

  # Add preprocessor definitions for the build version.
  target_compile_definitions(${TARGET} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
  target_compile_definitions(${TARGET} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
  target_compile_definitions(${TARGET} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
  target_compile_definitions(${TARGET} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
  target_compile_definitions(${TARGET} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

  # Disable Windows macros that collide with C++ standard library functions.
  target_compile_definitions(${TARGET} PRIVATE "NOMINMAX")

  # Add dependency libraries and include directories.
  target_link_libraries(${TARGET} PRIVATE flutter flutter_wrapper_app)
  target_link_libraries(${TARGET} PRIVATE "dwmapi.lib" shell32 shlwapi windowsapp ole32)
  target_compile_features(${TARGET} PRIVATE cxx_std_20)
  target_include_directories(${TARGET} PRIVATE "${CMAKE_SOURCE_DIR}")

  # Run the Flutter tool portions of the build. This must not be removed.
  add_dependencies(${TARGET} flutter_assemble)
endfunction()

folio_runner(${BINARY_NAME})
folio_runner(lifeos_editor)
target_compile_definitions(lifeos_editor PRIVATE "FOLIO_EDITOR")
