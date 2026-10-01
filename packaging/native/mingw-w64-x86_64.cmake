# Cross build of the bundled document tools for Windows x64 from a Linux host.
# Committed so the toolchain is part of the record rather than something each
# maintainer reconstructs; packaging/native/build_tools.py passes it via
# --toolchain and the native-tools workflow uses it on an Ubuntu runner.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(TOOLCHAIN_PREFIX x86_64-w64-mingw32)
set(CMAKE_C_COMPILER ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)
set(CMAKE_RC_COMPILER ${TOOLCHAIN_PREFIX}-windres)
set(CMAKE_AR ${TOOLCHAIN_PREFIX}-ar)
set(CMAKE_RANLIB ${TOOLCHAIN_PREFIX}-ranlib)

set(CMAKE_FIND_ROOT_PATH /usr/${TOOLCHAIN_PREFIX})
# Programs come from the host; headers and libraries must come from the target
# sysroot, or a configure check silently links the host's copy and the binary
# fails to run on Windows.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Windows 10 1903 is the floor the bundled tools target, matching the
# activeCodePage=UTF-8 manifest they carry.
add_definitions(-D_WIN32_WINNT=0x0A00)
