import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/uyap/uyap_case_data.dart';

/// What a case document's row shows when opened (15 Ekim 2026, the mockup
/// approved for banaozel too): who sent it and when, beyond the one date the
/// row has room for. An empty field is not a line.
List<(String, String)> uyapDocDetails(UyapCaseDocument d) => [
  if (d.description.trim().isNotEmpty &&
      d.description.trim().toLowerCase() != d.type.trim().toLowerCase())
    ('Açıklama', d.description.trim()),
  if (uyapDateText(d.sentToSystem).isNotEmpty)
    ('Sunulma', uyapDateText(d.sentToSystem)),
  if (uyapDateText(d.approved).isNotEmpty) ('Onay', uyapDateText(d.approved)),
  if (d.sender.trim().isNotEmpty) ('Gönderen', d.sender.trim()),
  if (d.number.trim().isNotEmpty) ('Evrak no', d.number.trim()),
  if (d.source.trim().isNotEmpty) ('Kaynak dosya', d.source.trim()),
];

/// The short form a pointer resting on the row is told; touch has none.
String uyapDocTip(UyapCaseDocument d) => [
  for (final (label, value) in uyapDocDetails(d))
    if (label == 'Sunulma' || label == 'Onay' || label == 'Gönderen')
      '$label: $value',
].join('\n');

/// "10.10.2026 14:32", the day alone when UYAP gave no hour; what could not
/// be read as it came.
String uyapDateText(String raw) {
  final s = raw.trim();
  final d = parseUyapDate(s);
  if (d == null) return s;
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${two(d.day)}.${two(d.month)}.${d.year}';
  return d.hour == 0 && d.minute == 0
      ? day
      : '$day ${two(d.hour)}:${two(d.minute)}';
}

/// A pointer to rest on: the desktop's, not a phone's.
bool get uyapDocHover =>
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

/// The arrow at the row's end that opens its details; it opens nothing else.
class UyapDocDetailsToggle extends StatelessWidget {
  const UyapDocDetailsToggle({
    super.key,
    required this.open,
    required this.onPressed,
  });

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: open ? 'Ayrıntıyı gizle' : 'Kim sundu, ne zaman sunuldu',
    // A finger's room on a phone, the row's on the desktop.
    visualDensity: uyapDocHover ? VisualDensity.compact : null,
    onPressed: onPressed,
    icon: AnimatedRotation(
      turns: open ? .5 : 0,
      duration: const Duration(milliseconds: 150),
      child: Icon(
        Icons.expand_more_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// The opened details, under the row, indented to its text.
class UyapDocDetails extends StatelessWidget {
  const UyapDocDetails({super.key, required this.details, this.indent = 0});

  final List<(String, String)> details;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    const value = TextStyle(fontSize: 12.5);
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.primary, width: 2)),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // Narrow, a phone's: each label over its value.
            final stacked = box.maxWidth < 320;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (name, text) in details)
                  Padding(
                    padding: EdgeInsets.only(bottom: stacked ? 5 : 3),
                    child: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: label),
                              SelectableText(text, style: value),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 104,
                                child: Text(name, style: label),
                              ),
                              Expanded(
                                child: SelectableText(text, style: value),
                              ),
                            ],
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
