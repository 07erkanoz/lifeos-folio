/// Türk e-imza PKCS#11 modül algılama.
///
/// Bilinen ESHS (Elektronik Sertifika Hizmet Sağlayıcısı) driver'larının
/// dosya sistemi yollarını tarayarak kurulu olanları döndürür.
library;

import 'dart:io';

/// Algılanan PKCS#11 modül bilgisi.
class Pkcs11ModuleInfo {
  final String name;
  final String provider;
  final String path;

  const Pkcs11ModuleInfo({
    required this.name,
    required this.provider,
    required this.path,
  });

  @override
  String toString() => '$name ($provider) → $path';
}

/// Kurulu PKCS#11 modüllerini algıla.
///
/// Bilinen Türk e-imza sağlayıcılarının driver yollarını kontrol eder.
/// Kullanıcının kendi modül yolunu da ekleyebilmesi için [extraPaths] parametresi.
List<Pkcs11ModuleInfo> detectInstalledModules({List<String>? extraPaths}) {
  final candidates = _getKnownModules();
  final found = <Pkcs11ModuleInfo>[];
  final seen = <String>{};

  void add(String name, String provider, String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final resolved = file.resolveSymbolicLinksSync();
      if (!seen.add(resolved)) return;
      found.add(
        Pkcs11ModuleInfo(name: name, provider: provider, path: resolved),
      );
    } on FileSystemException {
      // A missing or inaccessible candidate must not stop other drivers.
    }
  }

  for (final candidate in candidates) {
    for (final path in candidate.paths) {
      add(candidate.name, candidate.provider, path);
    }
  }

  // Kullanıcının eklediği özel yollar
  if (extraPaths != null) {
    for (final path in extraPaths) {
      final name = path.split(Platform.pathSeparator).last;
      add(name, 'Özel', path);
    }
  }

  return found;
}

// ─── Bilinen modüller ─────────────────────────────────────────────────

class _ModuleCandidate {
  final String name;
  final String provider;
  final List<String> paths;

  const _ModuleCandidate(this.name, this.provider, this.paths);
}

List<_ModuleCandidate> _getKnownModules() {
  if (Platform.isWindows) return _windowsModules();
  if (Platform.isLinux) return _linuxModules();
  if (Platform.isMacOS) return _macosModules();
  return [];
}

List<_ModuleCandidate> _windowsModules() {
  final sys32 =
      '${Platform.environment['SYSTEMROOT'] ?? 'C:\\Windows'}\\System32';
  final sysWow =
      '${Platform.environment['SYSTEMROOT'] ?? 'C:\\Windows'}\\SysWOW64';
  final programFiles =
      Platform.environment['ProgramFiles'] ?? 'C:\\Program Files';
  final programFilesX86 =
      Platform.environment['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)';

  return [
    _ModuleCandidate('AKİS (TÜBİTAK)', 'Kamu SM', [
      '$sys32\\akisp11.dll',
      '$sysWow\\akisp11.dll',
    ]),
    _ModuleCandidate('SafeSign', 'AET Europe / E-Tuğra', [
      '$sys32\\aetpkss1.dll',
      '$programFiles\\AET Europe\\SafeSign\\aetpkss1.dll',
      '$programFilesX86\\AET Europe\\SafeSign\\aetpkss1.dll',
    ]),
    _ModuleCandidate('GemSafe', 'Gemalto/Thales', [
      '$sys32\\gclib.dll',
      '$programFiles\\Gemalto\\Classic Client\\BIN\\gclib.dll',
    ]),
    _ModuleCandidate('SafeNet eToken', 'Thales', ['$sys32\\eTPkcs11.dll']),
    _ModuleCandidate('OpenSC', 'OpenSC Project', [
      '$programFiles\\OpenSC Project\\OpenSC\\pkcs11\\opensc-pkcs11.dll',
    ]),
  ];
}

List<_ModuleCandidate> _linuxModules() {
  return const [
    _ModuleCandidate('AKİS (TÜBİTAK)', 'Kamu SM', [
      '/usr/lib/akia/libakisp11.so',
      '/usr/lib/libakisp11.so',
      '/usr/lib/x86_64-linux-gnu/libakisp11.so',
      '/usr/local/lib/libakisp11.so',
    ]),
    _ModuleCandidate('SafeSign', 'AET Europe / E-Tuğra', [
      '/usr/lib/libaetpkss.so',
      '/usr/lib/libaetpkss.so.3',
      '/usr/lib/x86_64-linux-gnu/libaetpkss.so',
    ]),
    _ModuleCandidate('GemSafe', 'Gemalto/Thales', [
      '/usr/lib/libgclib.so',
      '/usr/local/lib/libgclib.so',
    ]),
    _ModuleCandidate('SafeNet eToken', 'Thales', ['/usr/lib/libeTPkcs11.so']),
    _ModuleCandidate('OpenSC', 'OpenSC Project', [
      '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so',
      '/usr/lib64/opensc-pkcs11.so',
      '/usr/lib/opensc-pkcs11.so',
    ]),
  ];
}

List<_ModuleCandidate> _macosModules() {
  return const [
    _ModuleCandidate('AKİS (TÜBİTAK)', 'Kamu SM', [
      '/usr/local/lib/libakisp11.dylib',
      '/Library/Frameworks/AKISManager.framework/libakisp11.dylib',
    ]),
    _ModuleCandidate('SafeSign', 'AET Europe / E-Tuğra', [
      '/usr/local/lib/libaetpkss1.dylib',
      '/Library/Frameworks/libaetpkss1.dylib',
    ]),
    _ModuleCandidate('SafeNet eToken', 'Thales', [
      '/usr/local/lib/libeTPkcs11.dylib',
    ]),
    _ModuleCandidate('OpenSC', 'OpenSC Project', [
      '/Library/OpenSC/lib/opensc-pkcs11.so',
      '/usr/local/lib/opensc-pkcs11.so',
      // Card makers' installers write to /usr/local on Apple Silicon too;
      // only Homebrew, from which OpenSC may also come, keeps its own place.
      '/opt/homebrew/lib/opensc-pkcs11.so',
    ]),
  ];
}
