"""Writes test/fixtures/ceza_altin.json.gz: golden cases for the Dart port of
banaozel's ceza_hesap.py (lib/services/legal/criminal_calculator.dart).

Each case is {girdi, bugun, cikti, metin}: the input, the day Python took as
"today" (the decision date when the input names none), Python's `hesapla`
output in JSON form and its `metin` text. The inputs are every input the
Python tests use (captured by running them) and a sweep over every crime,
several event dates around its versions and the options it accepts.

JSON form of `hesapla`: a fraction is [numerator, denominator], a date
"YYYY-MM-DD", a crime and a qualifying circumstance their code, a version
(Surum) and a scenario (Senaryo) a map of their fields. An input Python
raises on is stored with cikti = {"istisna": <exception class>}.

The "table freshness" line of `metin` reads a server-side audit file; it is
generated here with no such file, which is also what Folio has.

Usage (pytest is needed for the capture):
  ~/projeler/banaozel/server/.venv/bin/python tool/ceza/altin_uret.py
"""
from __future__ import annotations

import dataclasses
import gzip
import datetime as dt
import itertools
import json
import os
import random
import sys
from fractions import Fraction

KOK = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUNUCU = os.environ.get("BANAOZEL_SERVER") or os.path.expanduser("~/projeler/banaozel/server")
sys.path.insert(0, SUNUCU)

import ceza_hesap as ch  # noqa: E402

BUGUN = dt.date(2026, 10, 1)
KARAR = "01.10.2026"


class _SabitGun(dt.date):
    """`date` whose today() is BUGUN, so cases without a decision date stay fixed."""

    @classmethod
    def today(cls):
        return cls(BUGUN.year, BUGUN.month, BUGUN.day)


def jsonla(x):
    if isinstance(x, bool) or x is None or isinstance(x, (int, str)):
        return x
    if isinstance(x, Fraction):
        return [x.numerator, x.denominator]
    if isinstance(x, dt.date):
        return x.isoformat()
    if isinstance(x, (ch.Suc, ch.Nitelikli)):
        return x.kod
    if isinstance(x, (ch.Surum, ch.Senaryo)):
        return {f.name: jsonla(getattr(x, f.name)) for f in dataclasses.fields(x)}
    if isinstance(x, dict):
        return {str(k): jsonla(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [jsonla(v) for v in x]
    raise TypeError(type(x))


def calistir(girdi: dict) -> dict:
    try:
        cikti = jsonla(ch.hesapla(girdi))
    except Exception as e:  # noqa: BLE001 — the Dart side must throw on the same inputs
        return {"girdi": girdi, "bugun": BUGUN.isoformat(), "cikti": {"istisna": type(e).__name__},
                "metin": None}
    return {"girdi": girdi, "bugun": BUGUN.isoformat(), "cikti": cikti, "metin": ch.metin(girdi)}


# ─── inputs of the Python tests ───

def test_girdileri() -> list[dict]:
    import pytest

    kayit: list[dict] = []
    asil = ch.hesapla

    def kaydeden(girdi):
        kayit.append(json.loads(json.dumps(girdi, default=str)))
        return asil(girdi)

    class Eklenti:
        @pytest.hookimpl(tryfirst=True)
        def pytest_sessionstart(self, session):
            ch.hesapla = kaydeden

    yol = os.path.join(SUNUCU, "tests", "test_ceza_hesap.py")
    kod = pytest.main(["-q", "-p", "no:cacheprovider", yol], plugins=[Eklenti()])
    ch.hesapla = asil
    if kod != 0:
        raise SystemExit(f"Python tests failed ({kod}); goldens not written")
    return kayit


# ─── sweep ───

def gunler(suc: ch.Suc, nitelikli: list[ch.Nitelikli]) -> list[str]:
    """Event dates around each version of the crime and of its circumstances."""
    degisim = {s.bas for s in suc.surumler if s.bas}
    for n in nitelikli:
        degisim |= {b for b, _ in (*n.oran, *n.asgari, *n.sabit_ceza) if b}
    degisim |= {b for b, _ in suc.bent_asgari if b}
    if suc.tablo_baslangic:
        degisim.add(suc.tablo_baslangic)
    secim = {dt.date(2004, 6, 1), dt.date(2005, 6, 15), dt.date(2010, 3, 1), dt.date(2024, 1, 1)}
    for d in degisim:
        secim |= {d - dt.timedelta(days=1), d}
    return [f"{d:%d.%m.%Y}" for d in sorted(secim) if d <= dt.date(2026, 9, 30)]


def tarama() -> list[dict]:
    rnd = random.Random(20261113)
    vakalar: list[dict] = []
    tum_nit = list(ch.NITELIKLI.values())
    etkinler = sorted({*ch.ETKIN, "sorusturma_oncesi", "kovusturmada_ihtarsiz", "yakalandiktan_sonra_bilgi",
                       "mahkumiyet_sonrasi", "infaz_basladi", "bilinmeyen"})
    genel_k = list(ch.GENEL)
    for kod, suc in ch.SUCLAR.items():
        uyg = [n for n in tum_nit if not n.uygulanir or kod in n.uygulanir]
        uyg_k = [n.kod for n in uyg]
        bentler = sorted({*(b for _, t in suc.bent_asgari for b in t), *suc.bent_baslangic, *suc.bent_onceki,
                          *suc.mulga_bentler})
        if kod == "TCK 82/1":
            bentler += ["d", "e", "f-gebe"]
        tarihler = gunler(suc, uyg)
        # Every option alone on three dates (the earliest, one around a change, today's text); every
        # other date gets the plain case and random mixes, which keeps the file a few thousand cases.
        tam = {tarihler[0], tarihler[len(tarihler) // 2], tarihler[-1]}
        for t in tarihler:
            temel = {"olay_tarihi": t, "suc": kod, "karar_tarihi": KARAR}
            vakalar.append(dict(temel))
            if t in tam:
                vakalar += [{**temel, "nitelikli": [n]} for n in uyg_k]
                vakalar += [{**temel, g: True} for g in genel_k]
                vakalar += [{**temel, "fail_yas_grubu": y} for y in ("12-15", "15-18", "65+")]
                vakalar += [{**temel, "bent": b} for b in bentler]
                if suc.etkin_pismanlik:
                    vakalar += [{**temel, "etkin_pismanlik": e} for e in etkinler]
            # Random mixes: several circumstances, general rules, age, women, effective remorse.
            for _ in range(2):
                g = dict(temel)
                if uyg_k:
                    g["nitelikli"] = rnd.sample(uyg_k, min(len(uyg_k), rnd.randint(1, 3)))
                for k in genel_k:
                    if rnd.random() < 0.3:
                        g[k] = True
                if rnd.random() < 0.4:
                    g["fail_yas_grubu"] = rnd.choice(["12-15", "15-18", "65+"])
                if rnd.random() < 0.3:
                    g["kadina_karsi"] = True
                if bentler and rnd.random() < 0.5:
                    g["bent"] = rnd.choice(bentler)
                if rnd.random() < 0.3:
                    g["etkin_pismanlik"] = rnd.choice(etkinler)
                if rnd.random() < 0.3:
                    g["ayni_magdura_diger_suclar"] = rnd.sample(
                        [*ch.SUCLAR, "TCK 125/3-a", "TCK 125/4", "TCK 96", "125/3-b"], 2)
                if rnd.random() < 0.2:
                    g["karar_tarihi"] = t
                vakalar.append(g)
        # The circumstances in pairs (same paragraph, rate plus floor, increase plus reduction).
        ciftler = list(itertools.combinations(uyg_k, 2))
        for a, b in rnd.sample(ciftler, min(len(ciftler), 12)):
            vakalar.append({"olay_tarihi": "01.01.2024", "suc": kod, "karar_tarihi": KARAR, "nitelikli": [a, b]})
        # A late event with the decision date left out (Python's "today").
        vakalar.append({"olay_tarihi": "01.09.2026", "suc": kod})
    # Spellings, errors and odd inputs the tool may receive from a model.
    for suc in ("tck 86/1", "86/1", "TCK m.86/1", "TCK 144/1", "TCK 158/1-F", "TCK 158/1 (f)", "5237 sayılı TCK 102/1",
                "Türk Ceza Kanunu 141/1", "6136 sayılı Kanun m.13/1", "6136 13-1", "6136 SK 13/1", "6136/13-1",
                "TCK 82/1-d-bosanmis", "TCK 82/1-D-BOSANMIS", "TCK 142/1-b", "TCK 142/1-f", "TCK 302", "", None,
                "TCK 123/A", "tck 123/a-2", "5607 3/18", "5607 s.K. 3/1", 86):
        vakalar.append({"olay_tarihi": "01.01.2024", "suc": suc, "karar_tarihi": KARAR})
    for t in ("2024-01-01", "1.1.2024", "01/01/2024", "01-01-2024", "2024-01-01T10:00:00", "bugün", "", None,
              "31.02.2024", "29.02.2024", "29.02.2023"):
        vakalar.append({"olay_tarihi": t, "suc": "TCK 86/1", "karar_tarihi": KARAR})
    for nit in (["TCK 999"], ["86/3-e", "TCK 86/3-e"], ["TCK 86/3 e", "tck 87/1"], "TCK 87/1", ["TCK 141/1"]):
        vakalar.append({"olay_tarihi": "01.01.2024", "suc": "TCK 86/1", "karar_tarihi": KARAR, "nitelikli": nit})
    for kw in ({"tesebbus": "false"}, {"tesebbus": 0}, {"zincirleme": 1}, {"kadina_karsi": "evet"},
               {"bent": " (F) "}, {"bent": "()"}, {"fail_yas_grubu": "18+"}, {"etkin_pismanlik": ""}):
        vakalar.append({"olay_tarihi": "01.01.2024", "suc": "TCK 158/1", "karar_tarihi": KARAR, **kw})
    return vakalar


def main() -> None:
    os.environ["CEZA_TABLOSU_DURUM"] = os.path.join(KOK, "yok", "ceza_tablosu_durum.json")
    girdiler = test_girdileri()
    ch.date = _SabitGun
    girdiler += tarama()
    gorulen, vakalar = set(), []
    for g in girdiler:
        anahtar = json.dumps(g, sort_keys=True, ensure_ascii=False)
        if anahtar in gorulen:
            continue
        gorulen.add(anahtar)
        vakalar.append(calistir(g))
    # Gzipped: the texts repeat a lot, plain JSON would be tens of megabytes in the repository.
    hedef = os.path.join(KOK, "test", "fixtures", "ceza_altin.json.gz")
    veri = json.dumps(vakalar, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with open(hedef, "wb") as f:
        f.write(gzip.compress(veri, compresslevel=9, mtime=0))
    print(hedef, len(vakalar), "vaka")


if __name__ == "__main__":
    main()
