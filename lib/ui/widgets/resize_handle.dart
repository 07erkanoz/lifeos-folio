import 'package:flutter/material.dart';

/// The line between two columns, dragged to give one of them more room.
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({super.key, required this.onDrag});

  /// How far the line moved, rightwards positive.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: SizedBox(
        width: 7,
        child: Center(
          child: VerticalDivider(
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}
