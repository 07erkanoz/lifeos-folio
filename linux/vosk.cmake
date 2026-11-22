# Vosk (the wake word, speech recognised on this computer): the official
# release comes down once at build time, checked against its SHA-256; its
# library goes into the bundle. Dart opens it over dart:ffi
# (lib/services/voice/vosk.dart). From AvukatOS Asistan's vosk.cmake.
set(VOSK_VERSION "0.3.45")
set(VOSK_PACKAGE "vosk-linux-x86_64-${VOSK_VERSION}")
set(VOSK_SHA256 "bbdc8ed85c43979f6443142889770ea95cbfbc56cffb5c5dcd73afa875c5fbb2")
set(VOSK_DIR "${CMAKE_BINARY_DIR}/vosk")
if(NOT EXISTS "${VOSK_DIR}/${VOSK_PACKAGE}/libvosk.so")
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
if(EXISTS "${VOSK_DIR}/${VOSK_PACKAGE}/libvosk.so")
  install(FILES "${VOSK_DIR}/${VOSK_PACKAGE}/libvosk.so"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()
