// FOLIO PATCH: pages.
//
// The editor lays its lines out on pages of a fixed text height, the way
// UYAP and the printed page do: a row that does not fit on what is left of
// a page starts the next one, and space above a paragraph goes with its
// first row. Where each child of the editor starts is passed down with its
// constraints, so a line is laid out again only when the place it starts
// at changes.

import 'package:flutter/foundation.dart' show immutable, protected;
import 'package:flutter/rendering.dart';

/// Where the pages of an editor are, in its own coordinates: page `k`'s
/// text area runs from `k * stride - offset` to `k * stride - offset +
/// height`.
@immutable
class QuillPageGeometry {
  const QuillPageGeometry({
    required this.height,
    required this.stride,
    this.offset = 0,
  }) : assert(height > 0 && stride >= height);

  /// How tall the text area of one page is.
  final double height;

  /// From the top of one page's text area to the top of the next: the text
  /// area, then the bottom margin, the room between sheets and the next
  /// page's top margin.
  final double stride;

  /// How far below the top of the first page's text area the coordinates
  /// start: something laid out on the pages further down, such as a table
  /// cell, sees them from where it is.
  final double offset;

  /// The same pages seen from [by] further down.
  QuillPageGeometry shifted(double by) => by == 0
      ? this
      : QuillPageGeometry(height: height, stride: stride, offset: offset + by);

  /// A tolerance for rows that end a hair past the text area, as a row laid
  /// out in fractional pixels can when UYAP's would end on it exactly.
  static const _epsilon = .01;

  /// The page [y] is on; a [y] in the room between two pages counts as the
  /// earlier one.
  int pageOf(double y) => y + offset < 0 ? 0 : ((y + offset) / stride).floor();

  double topOf(int page) => page * stride - offset;
  double bottomOf(int page) => page * stride - offset + height;

  /// How far a row from [top] to [bottom] has to move down to start the
  /// next page, or 0 where it fits. One taller than a whole page is left
  /// where it is when it already starts a page.
  double push(double top, double bottom) {
    final page = pageOf(top);
    if (bottom <= bottomOf(page) + _epsilon) return 0;
    if (top <= topOf(page) + _epsilon) return 0;
    return topOf(page + 1) - top;
  }

  @override
  bool operator ==(Object other) =>
      other is QuillPageGeometry &&
      other.height == height &&
      other.stride == stride &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(height, stride, offset);
}

/// Something that lays out on pages what it holds, where no constraints can
/// say so: a line holding a table, and a table holding cells. What is laid
/// out below it asks for its pages with [pagesFromHost], and is laid out
/// again whenever where it sits on them changes.
mixin QuillPagedHost on RenderObject {
  /// The pages as seen from the top of [child], one of this object's own
  /// children, or null when it is not laid out on pages.
  QuillPageGeometry? pagesFor(RenderObject child);

  final Map<RenderObject, RenderObject> _dependents = {};

  /// Whether something below asked for its pages, and so breaks its own.
  bool get hasPagedDependents {
    _dependents.removeWhere((dependent, _) => !dependent.attached);
    return _dependents.isNotEmpty;
  }

  /// Lays out again what asked for its pages below [under], or below any
  /// child: called from [performLayout] when where it sits has changed.
  @protected
  void relayoutPagedDependents({RenderObject? under}) {
    if (_dependents.isEmpty) return;
    invokeLayoutCallback<Constraints>((_) {
      _dependents.removeWhere((dependent, _) => !dependent.attached);
      for (final MapEntry(key: dependent, value: child)
          in _dependents.entries) {
        if (under == null || identical(child, under)) {
          dependent.markNeedsLayout();
        }
      }
    });
  }
}

/// The pages [object] is laid out on, from the nearest [QuillPagedHost]
/// above it, which then lays it out again when they move.
QuillPageGeometry? pagesFromHost(RenderObject object) {
  var child = object;
  var node = object.parent;
  while (node != null) {
    if (node is QuillPagedHost) {
      node._dependents[object] = child;
      return node.pagesFor(child);
    }
    child = node;
    node = node.parent;
  }
  return null;
}

/// Box constraints that also say where on the pages a child starts.
class PagedBoxConstraints extends BoxConstraints {
  const PagedBoxConstraints({
    required this.pages,
    required this.top,
    super.minWidth,
    super.maxWidth,
    super.minHeight,
    super.maxHeight,
  });

  PagedBoxConstraints.from(BoxConstraints box,
      {required this.pages, required this.top})
      : super(
          minWidth: box.minWidth,
          maxWidth: box.maxWidth,
          minHeight: box.minHeight,
          maxHeight: box.maxHeight,
        );

  final QuillPageGeometry pages;

  /// Where the child's top is, in the editor's coordinates.
  final double top;

  @override
  bool operator ==(Object other) =>
      other is PagedBoxConstraints &&
      super == other &&
      other.pages == pages &&
      other.top == top;

  @override
  int get hashCode => Object.hash(super.hashCode, pages, top);
}
