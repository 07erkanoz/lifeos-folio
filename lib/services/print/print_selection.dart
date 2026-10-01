/// Which pages to print, in what order, and how many times: what a print
/// screen asks, as Word asks it.
library;

enum PrintPages { all, current, custom }

enum PrintParity { all, odd, even }

abstract final class PrintSelection {
  /// The pages [text] names, as Word reads a page range: numbers and ranges
  /// apart by commas or semicolons, a range open at either end reaching the
  /// first or last page ("1-3, 5, 8-"). Null when [text] names none, or a
  /// page the document does not have.
  static List<int>? parse(String text, int pageCount) {
    final parts = text
        .split(RegExp(r'[,;]'))
        .map((p) => p.replaceAll(' ', ''))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final pages = <int>[];
    for (final part in parts) {
      final range = RegExp(r'^(\d*)-(\d*)$').firstMatch(part);
      if (range != null) {
        final from = range[1]!.isEmpty ? 1 : int.parse(range[1]!);
        final to = range[2]!.isEmpty ? pageCount : int.parse(range[2]!);
        if (from < 1 || to > pageCount || from > to) return null;
        for (var p = from; p <= to; p++) {
          pages.add(p);
        }
        continue;
      }
      final page = int.tryParse(part);
      if (page == null || page < 1 || page > pageCount) return null;
      pages.add(page);
    }
    return pages;
  }

  /// The pages to print, from 1, in order: all of them, the [current] one,
  /// or those [range] names, then only the odd or the even ones.
  static List<int>? pages({
    required int pageCount,
    required PrintPages which,
    int current = 1,
    String range = '',
    PrintParity parity = PrintParity.all,
  }) {
    final chosen = switch (which) {
      PrintPages.all => [for (var p = 1; p <= pageCount; p++) p],
      PrintPages.current => [current.clamp(1, pageCount)],
      PrintPages.custom => parse(range, pageCount),
    };
    if (chosen == null) return null;
    return [
      for (final p in chosen)
        if (parity == PrintParity.all || (parity == PrintParity.odd) == p.isOdd)
          p,
    ];
  }

  /// [pages] as they come off the printer for [copies] copies: whole copies
  /// one after another when [collate]d, else each page [copies] times.
  static List<int> sheets(
    List<int> pages, {
    int copies = 1,
    bool collate = true,
  }) {
    final n = copies < 1 ? 1 : copies;
    return collate
        ? [for (var c = 0; c < n; c++) ...pages]
        : [
            for (final p in pages)
              for (var c = 0; c < n; c++) p,
          ];
  }
}
