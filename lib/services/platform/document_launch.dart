import 'dart:io';

/// Shell verbs and ordinary launches share one parser, including warm launches.
class DocumentLaunch {
  final List<String> paths;
  final bool edit;
  const DocumentLaunch(this.paths, {this.edit = false});
  factory DocumentLaunch.parse(List<String> arguments) {
    var edit = false, literal = false;
    final paths = <String>[];
    for (final argument in arguments) {
      if (!literal && argument == '--') {
        literal = true;
        continue;
      }
      if (!literal && argument == '--edit') {
        edit = true;
        continue;
      }
      if (!literal && argument.startsWith('-')) continue;
      paths.add(File(argument).absolute.path);
    }
    return DocumentLaunch(paths, edit: edit);
  }
  List<String> get arguments => [if (edit) '--edit', '--', ...paths];
}
