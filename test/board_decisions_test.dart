import 'package:evrak_convert/services/legal/board_decisions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Uyuşmazlık Mahkemesi: the result table as the site gives it', () {
    const html =
        '''<span>"kamulaştırmasız" sonuçları: 1698 dosya bulundu.</span>
<table><tr><th>Esas Numarası</th></tr>
<tr>
  <td>2026/206</td><td>2026/331</td><td>15/06/2026</td><td>
    <a href='Uploads/2026-206.pdf' class="grid-link" target="_blank">Görüntüle</a> |
    <a href='Uploads/2026-206.pdf' download class="grid-link">İndir</a>
  </td>
</tr></table>''';
    final (total, rows) = BoardDecisions.uyusmazlikRows(html);
    expect(total, 1698);
    expect(rows.single, {
      'kimlik': 'uyusmazlik:2026-206',
      'mahkeme': 'Uyuşmazlık Mahkemesi',
      'esas': '2026/206',
      'karar': '2026/331',
      'tarih': '15.06.2026',
    });
  });

  test('Rekabet Kurulu: one decision a block', () {
    const html = '''Toplam : 5847
<table><tr><td>Yayımlanma Tarihi :</td><td>12.11.2026</td><td>Karar Sayısı :</td><td>26-32/938-396</td>
<td><a href="/tr/KararlaIlgiliDavalar?kararId=fcdd5838-189d-46c7-a5ba-3ec07d9c00c6">Kararla ilgili davaları göster</a></td></tr>
<tr><td>Karar Tarihi :</td><td>3.9.2026</td><td>Karar Türü :</td><td>Birleşme ve Devralma</td></tr>
<tr><td><a href="/Karar?kararId=fcdd5838-189d-46c7-a5ba-3ec07d9c00c6">SABIC Europe B.V.nin tek kontrolünün AEQH38 GmbH tarafından devralınması işlemi.</a></td></tr></table>''';
    final (total, rows) = BoardDecisions.rekabetRows(html);
    expect(total, 5847);
    final r = rows.single;
    expect(r['kimlik'], 'rekabet:fcdd5838-189d-46c7-a5ba-3ec07d9c00c6');
    expect(r['karar'], '26-32/938-396');
    expect(r['tarih'], '3.9.2026');
    expect(r['tur'], 'Birleşme ve Devralma');
    expect(r['konu'], contains('devralınması'));
  });

  test('an id that is not one of theirs is not fetched', () async {
    final b = BoardDecisions(
      download: (_) async => throw StateError('istenmedi'),
    );
    expect((await b.read('uyusmazlik:../../etc'))['durum'], 'yok');
    expect((await b.read('baska:1'))['durum'], 'yok');
  });
}
