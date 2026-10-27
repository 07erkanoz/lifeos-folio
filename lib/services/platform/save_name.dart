import 'package:path/path.dart' as p;

/// [path] as typed in the system's save screen, given [extension] when
/// the name typed has none: a name whose extension was deleted went to
/// disk without one, and opened in nothing.
String withExtension(String path, String extension) {
  final typed = p.extension(path);
  if (extension.isEmpty || (typed.isNotEmpty && typed != '.')) return path;
  final base = path.endsWith('.') ? path.substring(0, path.length - 1) : path;
  return '$base.$extension';
}
