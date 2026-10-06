import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/layout/list_markers.dart';

/// List numbers and bullets as UYAP's own paragraph view draws them.
void main() {
  test('a number reads as each of UYAP\'s number kinds', () {
    expect(ListMarkers.label('NUMBER_TYPE_NUMBER_DOT', 3), '3.');
    expect(ListMarkers.label('NUMBER_TYPE_NUMBER_TRE', 3), '3-');
    expect(ListMarkers.label('NUMBER_TYPE_NUMBER_PARANTHESE', 3), '3)');
    expect(ListMarkers.label('NUMBER_TYPE_NUMBER_D_PARANTHESE', 3), '(3)');
    expect(ListMarkers.label('NUMBER_TYPE_CHAR_SMALL_DOT', 3), 'c.');
    expect(ListMarkers.label('NUMBER_TYPE_CHAR_BIG_DOT', 3), 'C.');
    expect(ListMarkers.label('NUMBER_TYPE_CHAR_BIG_DOT', 27), 'AA.');
    expect(ListMarkers.label('NUMBER_TYPE_ROMAN_SMALL_DOT', 4), 'iv.');
    expect(ListMarkers.label('NUMBER_TYPE_ROMAN_BIG_TRE', 9), 'IX-');
    // A numbered item that names no kind is "n.", as UYAP draws it.
    expect(ListMarkers.label(null, 2), '2.');
  });

  test('an item is numbered within its own list, at its own level, back to '
      'a higher level', () {
    DocBlock item(int id, int level, {bool numbered = true}) => DocBlock(
      plainText: '',
      listType: numbered ? DocListType.ordered : DocListType.unordered,
      listId: id,
      listLevel: level,
    );
    final blocks = [
      item(1, 1), // 1
      item(1, 1), // 2
      DocBlock(plainText: 'ara'),
      item(1, 1), // 3: the same list goes on after a paragraph
      item(2, 1), // 1: another list
      item(1, 2), // 1: a level down
      item(1, 2), // 2
      item(1, 1), // 4
      item(1, 2), // 1: a higher level started the lower one over
    ];
    expect(ListMarkers.numbers(blocks), {
      0: 1,
      1: 2,
      3: 3,
      4: 1,
      5: 1,
      6: 2,
      7: 4,
      8: 1,
    });
  });

  test('a list made in the editor, which names no list, is the items next '
      'to each other', () {
    DocBlock item() =>
        DocBlock(plainText: '', listType: DocListType.ordered, listLevel: 1);
    expect(
      ListMarkers.numbers([item(), item(), DocBlock(plainText: 'ara'), item()]),
      {0: 1, 1: 2, 3: 1},
    );
  });

  test('the marker sits in the indent, where UYAP puts it', () {
    // "1." at 12 point, 6 points wide, beside text starting at 25.
    final number = ListMarkers.numberAt(
      textStart: 25,
      advance: 6,
      row: 14,
      size: 12,
    );
    expect(number.x, 25 - 15 - 2);
    expect(number.baseline, 7 - 3 + 1 + 6);
    // Wider than 12 points, it reaches further left.
    expect(
      ListMarkers.numberAt(textStart: 25, advance: 14, row: 14, size: 12).x,
      25 - 15 - 4,
    );
    final bullet = ListMarkers.bulletAt(textStart: 25, row: 14, size: 12);
    expect((bullet.x, bullet.y, bullet.side), (10.0, 6.0, 5.0));
  });

  test('lists made in the editor are saved as UYAP writes lists: a list of '
      'their own each, at level 1, "1." and a dot, 25 points in', () {
    final delta = Delta()
      ..insert('Bir')
      ..insert('\n', {'list': 'ordered'})
      ..insert('İki')
      ..insert('\n', {'list': 'ordered'})
      ..insert('Ara\n')
      ..insert('Yeni liste')
      ..insert('\n', {'list': 'ordered'})
      ..insert('Madde')
      ..insert('\n', {'list': 'bullet'});
    final blocks = DocDeltaMap.deltadanModel(delta).blocks;
    final items = blocks.where((b) => b.listType != DocListType.none).toList();
    expect(items.map((b) => b.listId).toList(), [1, 1, 2, 2]);
    expect(items.map((b) => b.listLevel).toSet(), {1});
    expect(items.map((b) => b.leftIndent).toSet(), {25.0});
    expect(items[0].numberType, 'NUMBER_TYPE_NUMBER_DOT');
    expect(items[3].bulletType, 'BULLET_TYPE_ELLIPSE');
    // Numbered as UYAP then numbers them: the second list starts over.
    expect(ListMarkers.numbers(blocks).values.toList(), [1, 2, 1]);
  });
}
