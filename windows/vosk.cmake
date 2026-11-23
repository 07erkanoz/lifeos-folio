# Vosk (Folio Ajan's wake word, speech recognised on this computer): the
# official Windows release comes down once at build time, checked against
# its SHA-256, as on Linux (linux/vosk.cmake). libvosk.dll and the MinGW
# runtime it was built with go beside the executables; Dart opens it over
# dart:ffi (lib/services/voice/vosk.dart).
set(VOSK_VERSION "0.3.45")
set(VOSK_PACKAGE "vosk-win64-${VOSK_VERSION}")
set(VOSK_SHA256 "f1dcc9cca460630f81ea8f71794f69c80bed6556d2a4e6237b5785e1d2dff34b")
set(VOSK_DIR "${CMAKE_BINARY_DIR}/vosk")
if(NOT EXISTS "${VOSK_DIR}/${VOSK_PACKAGE}/libvosk.dll")
  file(DOWNLOAD
    "https://github.com/alphacep/vosk-api/releases/download/v${VOSK_VERSION}/${VOSK_PACKAGE}.zip"
    "${VOSK_DIR}/${VOSK_PACKAGE}.zip"
    EXPECTED_HASH SHA256=${VOSK_SHA256}
    STATUS VOSK_STATUS TLS_VERIFY ON)
  list(GET VOSK_STATUS 0 VOSK_CODE)
  if(VOSK_CODE EQUAL 0)
    file(ARCHIVE_EXTRACT INPUT "${VOSK_DIR}/${VOSK_PACKAGE}.zip"
      DESTINATION "${VOSK_DIR}")
  else()
    message(WARNING "Vosk indirilemedi (${VOSK_STATUS}); sesle açma bu derlemede çalışmaz.")
  endif()
endif()
if(EXISTS "${VOSK_DIR}/${VOSK_PACKAGE}/libvosk.dll")
  install(FILES
    "${VOSK_DIR}/${VOSK_PACKAGE}/libvosk.dll"
    "${VOSK_DIR}/${VOSK_PACKAGE}/libstdc++-6.dll"
    "${VOSK_DIR}/${VOSK_PACKAGE}/libgcc_s_seh-1.dll"
    "${VOSK_DIR}/${VOSK_PACKAGE}/libwinpthread-1.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()
