/// Where a table's columns go, for the preview and the editor alike.
///
/// Read off UYAP's own layout of the tables in a real archive and in
/// test/fixtures/pages: a table is as wide as the text area cut down to a
/// whole point (453.54 points of text area hold a table 453 wide), and each
/// column edge falls on the whole point nearest its share of that width —
/// four even columns of 453 are 113, 114, 113 and 113, two are 227 and 226.
/// A cell draws its text against its edges, and the lines between cells take
/// no room.
///
/// A Word document's table keeps its shares exactly.
library;

abstract final class TableColumns {
  /// The width of each of [count] columns in a text area [available] points
  /// wide, sharing it by [shares] where the table names them and evenly where
  /// it does not.
  static List<double> widths(
    double available,
    int count, {
    List<double>? shares,
    bool whole = true,
  }) {
    if (count <= 0) return const [];
    final parts =
        shares != null &&
            shares.length >= count &&
            shares.take(count).every((s) => s > 0)
        ? shares.take(count).toList()
        : List<double>.filled(count, 1);
    final total = parts.fold<double>(0, (a, b) => a + b);
    if (!whole) return [for (final p in parts) available * p / total];
    final width = available.floorToDouble();
    final out = <double>[];
    var sum = 0.0;
    var previous = 0.0;
    for (final p in parts) {
      sum += p;
      final edge = (width * sum / total).roundToDouble();
      out.add(edge - previous);
      previous = edge;
    }
    return out;
  }
}
