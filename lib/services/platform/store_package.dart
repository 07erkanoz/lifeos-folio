import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Whether this Folio was installed from the Microsoft Store: Windows then
/// runs it with a package identity. The Store updates it, its manifest
/// names the file types and the context menu, and it keeps its data
/// outside AppData (see folioSupportDirectory), so Folio neither updates
/// itself nor writes those into the registry.
bool get runsFromStorePackage =>
    _packaged ??= Platform.isWindows && _hasPackageIdentity();
bool? _packaged;

@visibleForTesting
set debugRunsFromStorePackage(bool? value) => _packaged = value;

/// Windows' own answer: GetCurrentPackageFullName says
/// APPMODEL_ERROR_NO_PACKAGE for a process without a package.
bool _hasPackageIdentity() {
  const noPackage = 15700;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final fullName = kernel32
        .lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Uint16>),
          int Function(Pointer<Uint32>, Pointer<Uint16>)
        >('GetCurrentPackageFullName');
    final length = calloc<Uint32>();
    try {
      return fullName(length, nullptr) != noPackage;
    } finally {
      calloc.free(length);
    }
  } catch (_) {
    return false;
  }
}
