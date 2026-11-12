import 'dart:io';

/// Shell verbs and ordinary launches share one parser, including warm launches.
class DocumentLaunch {
  final List<String> paths;
  final bool edit;

  /// A live document's invitation Folio was started with
  /// (`lifeos-folio://katil/…`, see LiveLinks), not a document.
  final String? link;
  const DocumentLaunch(this.paths, {this.edit = false, this.link});
  factory DocumentLaunch.parse(List<String> arguments) {
    var edit = false, literal = false;
    String? link;
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
      if (argument.startsWith('lifeos-folio:')) {
        link = argument;
        continue;
      }
      if (!literal && argument.startsWith('-')) continue;
      paths.add(File(argument).absolute.path);
    }
    return DocumentLaunch(paths, edit: edit, link: link);
  }
  List<String> get arguments => [if (edit) '--edit', ?link, '--', ...paths];

  /// What the open Folio is handed when this one is started again: nothing
  /// when no document was named (its icon, the menu), that it shows its
  /// home page; [arguments] always hold '--' and never said so.
  List<String> get forwarded =>
      paths.isEmpty && link == null ? const [] : arguments;
}
