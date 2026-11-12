"""Writes assets/mevzuat/ceza_tablosu.json from banaozel's ceza_hesap.py.

The criminal-sentence tables live in one place, the Python module on the
banaozel server; Folio's Dart port reads this export instead of a hand copy,
so a table change there reaches Folio by running this script again.

Encoding: a fraction is [numerator, denominator], a date "YYYY-MM-DD" or
null (null = the law's first text). Lists keep the module's order, because
the computation depends on it (NITELIKLI order is the TCK 61 order).

Usage: python3 -I tool/ceza/disa_aktar.py [path/to/banaozel/server]
"""
from __future__ import annotations

import json
import os
import sys
from datetime import date
from fractions import Fraction

KOK = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUNUCU = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/projeler/banaozel/server")
sys.path.insert(0, SUNUCU)

import ceza_hesap as ch  # noqa: E402


def kesir(x) -> list[int]:
    f = Fraction(x)
    return [f.numerator, f.denominator]


def gun(d: date | None) -> str | None:
    return d.isoformat() if d else None


def kesir_ya(x):
    return None if x is None else kesir(x)


def surum(s: ch.Surum) -> dict:
    return {"bas": gun(s.bas), "alt": kesir(s.alt), "ust": kesir(s.ust), "adli_para": s.adli_para,
            "kadin_alt": kesir_ya(s.kadin_alt), "adli_para_ek": s.adli_para_ek, "kaynak": s.kaynak,
            "dogrulandi": s.dogrulandi}


def etkin_kaydi(t: tuple) -> dict:
    # Python reads these tuples by length: [2] is "fixed", [3] the lower end of
    # a mandatory range. The export names them so the Dart side needs no index.
    assert 2 <= len(t) <= 4, t
    return {"ad": t[0], "en_cok": kesir(t[1]), "sabit": bool(t[2]) if len(t) > 2 else False,
            "en_az": kesir(t[3]) if len(t) > 3 else None}


def suc(s: ch.Suc) -> dict:
    return {
        "kod": s.kod, "ad": s.ad, "surumler": [surum(x) for x in s.surumler],
        "sikayete_bagli": s.sikayete_bagli, "uzlastirma": s.uzlastirma, "uzlastirma_notu": s.uzlastirma_notu,
        "onodeme_ozel": s.onodeme_ozel, "sikayet_notu": s.sikayet_notu, "taksirli": s.taksirli,
        "vucut_kasten": s.vucut_kasten,
        "bent_asgari": [[gun(b), {k: kesir(v) for k, v in t.items()}] for b, t in s.bent_asgari],
        "bent_baslangic": {k: gun(v) for k, v in s.bent_baslangic.items()},
        "tablo_baslangic": gun(s.tablo_baslangic), "tablo_notu": s.tablo_notu,
        "etkin_pismanlik": s.etkin_pismanlik,
        "bent_onceki": {k: [gun(b), surum(x)] for k, (b, x) in s.bent_onceki.items()},
        "agir_ceza_listesi": s.agir_ceza_listesi,
        "etkin_ozel": {k: etkin_kaydi(v) for k, v in s.etkin_ozel.items()},
        "uzlastirma_yasak": s.uzlastirma_yasak,
        "mulga_bentler": {k: [h, a] for k, (h, a) in s.mulga_bentler.items()},
        "notlar": s.notlar,
    }


def nitelikli(n: ch.Nitelikli) -> dict:
    return {
        "kod": n.kod, "ad": n.ad, "en_az": kesir(n.en_az), "en_cok": kesir(n.en_cok),
        "asgari": [[gun(b), {k: kesir(v) for k, v in t.items()}] for b, t in n.asgari],
        "sikayeti_kaldirir": n.sikayeti_kaldirir, "uzlastirmayi_kaldirir": n.uzlastirmayi_kaldirir,
        "uygulanir": list(n.uygulanir), "kaynak": n.kaynak,
        "sabit_ceza": [[gun(b), {k: surum(v) for k, v in t.items()}] for b, t in n.sabit_ceza],
        "oran": [[gun(b), [kesir(a), kesir(c)]] for b, (a, c) in n.oran],
        "uzlastirma_notu": n.uzlastirma_notu, "adli_para_ek": n.adli_para_ek,
    }


def tablo() -> dict:
    return {
        "kaynak": "banaozel server/ceza_hesap.py (tool/ceza/disa_aktar.py ile)",
        "surum": ch.SURUM, "ay": ch.AY, "yil": ch.YIL,
        "muebbet": kesir(ch.MUEBBET), "agir_muebbet": kesir(ch.AGIR_MUEBBET),
        "suclar": [suc(s) for s in ch.SUCLAR.values()],
        "nitelikli": [nitelikli(n) for n in ch.NITELIKLI.values()],
        "etkin": {k: etkin_kaydi(v) for k, v in ch.ETKIN.items()},
        "genel": {k: {"ad": a, "en_az": kesir(x), "en_cok": kesir(y)} for k, (a, x, y) in ch.GENEL.items()},
        "yas": {k: {"oran": [[gun(b), kesir(o)] for b, o in oran],
                    "azami": [[gun(b), kesir(o)] for b, o in azami], "aciklama": ac}
                for k, (oran, azami, ac) in ch.YAS.items()},
        "donusum": {k: [[gun(b), {t: [kesir(a), kesir(u)] for t, (a, u) in d.items()}] for b, d in v]
                    for k, v in ch.DONUSUM.items()},
        "donusum_ad": dict(ch._DONUSUM_AD),
        "zincirleme_yasak": sorted(ch.ZINCIRLEME_YASAK),
        "temel_asgari": sorted(ch.TEMEL_ASGARI),
        "dmk48_turu": dict(ch.DMK48_TURU),
    }


def main() -> None:
    hedef = os.path.join(KOK, "assets", "mevzuat", "ceza_tablosu.json")
    with open(hedef, "w", encoding="utf-8") as f:
        json.dump(tablo(), f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(hedef, len(ch.SUCLAR), "suç,", len(ch.NITELIKLI), "nitelikli hâl")


if __name__ == "__main__":
    main()
