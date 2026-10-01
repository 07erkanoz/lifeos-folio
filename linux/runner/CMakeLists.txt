cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
# Folio and LifeOS Editör are one app built twice: the editor's runner is
# compiled with FOLIO_EDITOR, which asks the Dart side for its editor alone,
# and runs under an application id of its own, so docks and task bars keep
# its windows apart from Folio's. Both share the bundle's lib and data.
function(folio_runner TARGET APP_ID)
  add_executable(${TARGET}
    "main.cc"
    "my_application.cc"
    "file_actions.cc"
    "quick_search.cc"
    "spell_check.cc"
    "rich_clipboard.cc"
    "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  )

  # Apply the standard set of build settings.
  apply_standard_settings(${TARGET})

  # The GTK application id, per program.
  target_compile_definitions(${TARGET} PRIVATE APPLICATION_ID="${APP_ID}")

  # Add dependency libraries.
  target_link_libraries(${TARGET} PRIVATE flutter)
  target_link_libraries(${TARGET} PRIVATE PkgConfig::GTK)
  # Enchant is opened at run time, so only the loader is linked and
  # nothing has to be installed to build this.
  target_link_libraries(${TARGET} PRIVATE ${CMAKE_DL_LIBS})

  target_include_directories(${TARGET} PRIVATE "${CMAKE_SOURCE_DIR}")
  target_link_libraries(${TARGET} PRIVATE PkgConfig::X11)
endfunction()

pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)
folio_runner(${BINARY_NAME} "${APPLICATION_ID}")
folio_runner(${EDITOR_BINARY_NAME} "${EDITOR_APPLICATION_ID}")
target_compile_definitions(${EDITOR_BINARY_NAME} PRIVATE FOLIO_EDITOR)
