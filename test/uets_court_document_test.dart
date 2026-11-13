import 'package:evrak_convert/services/legal/deadlines/aidiyet.dart';
import 'package:evrak_convert/services/legal/deadlines/belge_turu.dart';
import 'package:flutter_test/flutter_test.dart';

// A remanded case's notice (13.11.2026): its package named one defendant
// and no lawyer, and brought the regional court's decision as
// "(3)KararIlami.udf". Folio gave it an appeal's time (istinaf) and asked
// the lawyer whom they act for, both told in the documents themselves.
const tensip = '''
TENSİP ZAPTI
(BOZMA)
ESAS NO : 2026/527 Esas
HAKİM : Fadime AYDENİZ 194060
DAVACI : GÖKTÜRK DERİ TURİZM GIDA İNŞAAT SANAYİ VE TİCARET
LİMİTED ŞİRKETİ -
VEKİLLERİ : Av. BURAK SOYBİR - [16062-60681-39374] UETS
Av. RASİM YILMAZ - [16129-21084-80644] UETS
DAVALILAR : 1- AYLA TAŞ-43810517740 - Örnek Mah. 1529 Sk. No: 4 İç Kapı No: 8
Manavgat/ ANTALYA
2- RECEP ALTIN-43879515428 -
VEKİLİ : Av. ERKAN ÖZ - [16698-96487-27452] UETS
DAVA : Tazminat (Haksız Fiilden Kaynaklanan)
1- Taraflara Duruşma gününü bildirir davetiye gönderilmesine,
''';

const bam = '''
T.C.
ANTALYA
BÖLGE ADLİYE MAHKEMESİ
  YEDİNCİ HUKUK DAİRESİ
İ S T İ N A F   K A R A R I
Esas No\t: 2024/269
Davacı\t: Göktürk Deri Limited Şirketi (0406031649000001)
Vekilleri\t:  Av. Burak Soybir, Av. Rasim Yılmaz
Davalılar\t: 1- Ayla Taş (TC 43810517740)
\t  2- Recep Altın (TC 43879515428)
Vekili\t: Av. Erkan Öz
Davanın Türü\t: Tazminat
…
V. KARAR
1)Yerel mahkeme kararının esası incelenmeksizin ORTADAN KALDIRILMASINA,
3)Dosya üzerinde yapılan inceleme neticesinde 29/09/2026 tarihinde HMK'nun 362. maddesi uyarınca kesin olarak oybirliği ile karar verildi.
''';

void main() {
  test('a decision named "KararIlami" is the regional court\'s when its '
      'heading says so; a final one brings no time', () {
    expect(
      BelgeTuruTespit.ekTurleri(['(3)KararIlami.udf']).single.tur,
      BelgeTuru.kararIlami,
    );
    expect(
      BelgeTuruTespit.inceltilmis(BelgeTuru.kararIlami, bam),
      BelgeTuru.istinafKarari,
    );
    expect(
      BelgeTuruTespit.inceltilmis(
        BelgeTuru.kararIlami,
        'T.C.\nYARGITAY\n3. Hukuk Dairesi\nKARAR',
      ),
      BelgeTuru.temyizKarari,
    );
    expect(
      BelgeTuruTespit.inceltilmis(
        BelgeTuru.kararIlami,
        'T.C.\nMANAVGAT 1. ASLİYE HUKUK MAHKEMESİ\nGEREKÇELİ KARAR',
      ),
      BelgeTuru.kararIlami,
    );
    expect(BelgeTuruTespit.kesinKarar(bam), isTrue);
    // Open to appeal: not final, whatever "kesin" it says elsewhere.
    expect(
      BelgeTuruTespit.kesinKarar(
        'Davanın KABULÜNE, kesin süre verilmesine, tebliğden itibaren iki '
        'hafta içinde istinaf yolu açık olmak üzere karar verildi.',
      ),
      isFalse,
    );
    expect(
      BelgeTuruTespit.kesinKarar('Davanın reddine karar verildi.'),
      isFalse,
    );
  });

  test('whose lawyer the lawyer is, from the document\'s heading', () {
    for (final text in [tensip, bam]) {
      final parties = belgedekiTaraflar(text);
      final ours = [
        for (final t in parties)
          if (vekilOlarakGeciyor(t.vekil, 'Av. Erkan ÖZ')) t,
      ];
      expect(ours.map((t) => t.rol).toSet(), {'DAVALI'});
      expect(ours.length, 2);
      expect(
        vekilOlarakGeciyor(
          parties.where((t) => t.rol == 'DAVACI').single.vekil,
          'Burak Soybir',
        ),
        isTrue,
      );
    }
    // The package's list: names and roles, lawyers apart; filled from the
    // documents, the defendant it left out added.
    final filled = vekilleriTamamla([
      (ad: 'AYLA TAŞ', rol: 'DAVALI', vekil: ''),
      (ad: 'ERKAN ÖZ', rol: 'Vekil', vekil: ''),
      (ad: 'AHMET ALTIN', rol: 'TANIK', vekil: ''),
    ], belgedekiTaraflar(tensip));
    expect(
      filled.firstWhere((t) => t.ad == 'AYLA TAŞ').vekil,
      contains('ERKAN ÖZ'),
    );
    expect(filled.any((t) => t.ad == 'RECEP ALTIN'), isTrue);
    expect(filled.firstWhere((t) => t.ad == 'AHMET ALTIN').vekil, isEmpty);
  });
}
