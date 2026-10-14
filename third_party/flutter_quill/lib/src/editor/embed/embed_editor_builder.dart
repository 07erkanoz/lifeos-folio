import 'package:flutter/widgets.dart';

import '../../document/nodes/leaf.dart' as leaf;
import 'embed_context.dart';

export './embed_context.dart';

abstract class EmbedBuilder {
  const EmbedBuilder();

  String get key;
  bool get expanded => true;

  WidgetSpan buildWidgetSpan(Widget widget) {
    return WidgetSpan(child: widget);
  }

  String toPlainText(leaf.Embed node) => leaf.Embed.kObjectReplacementCharacter;

  /// FOLIO PATCH: everything [build] draws [node] from, beyond the node
  /// itself and the editor's settings: the line it is in is kept, not built
  /// again, while this stays equal. Null (the default) for an embed drawn
  /// from what the line cannot see: its line is built every time.
  Object? keptBy(leaf.Embed node, {required bool readOnly}) => null;

  Widget build(
    BuildContext context,
    EmbedContext embedContext,
  );
}

typedef EmbedsBuilder = EmbedBuilder Function(leaf.Embed node);
