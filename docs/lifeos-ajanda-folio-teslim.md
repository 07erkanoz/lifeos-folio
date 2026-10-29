# Folio → LifeOS: kurulum profili ve ajanda bağlantısı (teslim notu)

Folio deposu `main`, 29 Ekim 2026. LifeOS deposuna dokunulmadı.

## Sürümler

| Görev | Sürüm | Kayıt | Durum |
|---|---|---|---|
| Kurulum profili | **1.7.8** (build 21) | `913f3a5`, sürüm kaydı `68acc55` | Kod GitHub'da; paket henüz derlenmedi |
| Ajanda bağlantısı | **1.8.0** (önerilen) | `31f8c24` | Kod GitHub'da; sürüm numarası paket derlenirken verilecek |

`git merge-base --is-ancestor 9e802f2 68acc55` doğru: 1.7.8, 9e802f2'yi ve bu görevin kaydını içeriyor.

**Paketler henüz sitede değil.** GitHub Actions'ın bu ayki ücretsiz kotası bitti (depo gizli). Bu bilgisayarda
derlenen paket glibc 2.44 istediği için Ubuntu 24.04 ve Debian 13 kullanıcılarında açılmaz; sitedeki Linux
paketi herkese gittiği için GitHub'ın Ubuntu 24.04 makinesinde derlenmeli. İndirme adresleri yayın olunca
şöyle olacak:

- `https://lifeos.com.tr/downloads/LifeOS-Folio-1.7.8-Linux-x64.tar.gz`
- `https://lifeos.com.tr/downloads/LifeOS-Ofis-1.7.8-Linux-x64.tar.gz`
- imzalı bilgi: `https://lifeos.com.tr/surum/stable/linux-x64.json`

`lifeos-folio` paketi `tools/site_surum.py --guncelle` ile siteden güncellenebilir.

## 1. Kurulum profili (1.7.8)

- Folio her açılışta (yalnız Linux), kayıtlı profilde avukat yoksa ve `~/.config/lifeos/folio-profil.json` varsa
  boş alanları dosyadan doldurup kaydeder, bir kez "LifeOS kurulumunda verdiğiniz bilgiler profilinize eklendi"
  der. Profilde avukat varsa hiçbir şey değişmez. Dosya yalnız okunur.
- Bilgiler bir kez verilir: ilk açılış adımında görülüp geçildiyse (değiştirilse ya da silinse de) bir daha
  önerilmez. Bunun izi Folio'nun kendi klasöründe `lifeos-profil-alindi` dosyasıdır.
- Ev bilgisayarı gibi bir kez boş açılmış Folio, 1.7.8'in ilk açılışında bilgileri alır.

## 2. Ajanda bağlantısı (1.8.0)

### Dosya: `$XDG_DATA_HOME/lifeos/folio-ajanda.json` (0600, atomik)

```json
{
  "schema": 1,
  "generated": "2026-10-29T23:30:24+03:00",
  "range": { "from": "2026-09-29", "to": "2027-02-26" },
  "events": [
    {
      "uid": "durusma-3f1c9a0d2b7e4c51",
      "kind": "durusma",
      "title": "Ön inceleme duruşması",
      "start": "2026-11-04T10:30:00+03:00",
      "allDay": false,
      "minutes": 60,
      "court": "Manavgat 3. İş Mahkemesi",
      "case": "2026/470",
      "client": "AYŞE KARACA",
      "status": "iptal",
      "updated": "2026-10-29T09:12:40+03:00"
    },
    {
      "uid": "gorev-cdd8a007548a7568",
      "kind": "gorev",
      "title": "Bilirkişi raporuna itiraz dilekçesi",
      "start": "2026-11-05",
      "allDay": true,
      "court": "Manavgat 3. İş Mahkemesi",
      "case": "2026/470",
      "done": true,
      "updated": "2026-10-29T23:30:00+03:00"
    }
  ]
}
```

Alanlar (`schema` 1 kalıyor, yenilerin hepsi isteğe bağlı):

| Alan | Ne zaman | Anlamı |
|---|---|---|
| `range.from`, `range.to` | her zaman | Kapsanan günler: bugünden 30 gün önce ile 120 gün sonrası, ikisi dahil. Bu aralıkta olup dosyada olmayan kayıt silinmiştir. |
| `uid` | her zaman | Kalıcı. Duruşma başka güne, saate, salona ya da mahkemeye alınsa da (UYAP kaydının kimliği aynı kaldıkça) ve iki portalın satırları birleşince değişmez. |
| `updated` | her zaman | Kaydın Folio'da son değiştiği an. Görevlerde Folio'nun kendi zamanı; duruşma ve sürelerde, kaydın değiştiğini gören ilk yazımın zamanı. |
| `done` | yalnız `true` iken | Biten görev ya da süre. Biten kayıtlar artık dosyada kalıyor. |
| `status` | yalnız `"iptal"` | UYAP'ın sonucu iptal ya da düştü diyen duruşma. (Bu bilgisayarın arşivinde böyle bir sonuç hiç görülmedi; metin "iptal" ya da "düş" içeriyorsa sayılıyor.) |
| `client` | yalnız ayar açıkken | Değişmedi; "Müvekkil adını LifeOS ajandasında göster" varsayılan kapalı. |
| `address` | yazılmıyor | Folio mahkeme adreslerini tutmuyor; alan hiç yazılmaz. |

Uyarı: bugünkü panel bilinmeyen alanları yok saydığı için `done: true` olan görevleri bitmemiş gibi gösterir;
panel `done`'u okumaya başlamalı.

### `lifeos_folio --ajanda-yaz`

- Pencere açmaz; istekleri işler, dosyayı yazar, 0 ile çıkar. Hata olursa Türkçe tek satır ve 1.
- Bu bilgisayarda gerçek programla 0,25 sn sürdü; açık bir Folio'nun yanında da 0 ile çıktı.
- **Ekran gerekir:** Folio'nun masaüstü motoru GTK'ya bağlı; `DISPLAY` ya da `WAYLAND_DISPLAY` yoksa açılamaz
  ("cannot open display", çıkış 1). Kullanıcı zamanlayıcısı grafik oturumda çalışmalı (ör. servis
  `After=graphical-session.target` ve `PartOf=graphical-session.target`, ortam `systemctl --user
  import-environment` ile alınmış). Çıktıya GTK'nın Atk uyarıları da düşebilir; zararsız.

### Gelen kutusu: `$XDG_DATA_HOME/lifeos/folio-istek/<uuid>.json`

- Görevdeki biçim aynen: `action` `ekle` (`kind` `gorev` ya da `sure`) ve `bitti` (yalnız görev).
  `start` `2026-11-05` ise gün boyu, saatli ise o an. `allDay`, `case`, `court`, `note` isteğe bağlı.
- `durusma` eklenmez: "Duruşmalar UYAP'tan gelir; Folio'ya el ile duruşma eklenmez." hatası döner.
- `case` verildiyse kayıt o numaralı tek dosyaya bağlanır; `court` da verildiyse önce ikisine birlikte bakılır.
  Dosya yoksa ya da aynı numaralı birden çok dosya varsa hata döner; Folio dosya ya da müvekkil açmaz.
- İşlenir: açılışta, açıkken 20 saniyede bir ve `--ajanda-yaz`'da. Her istek önce adıyla sahiplenilir
  (`.alindi-<uuid>.<pid>`), bir kez işlenir ve `islendi/<uuid>.json`'a (0600) yalnız sonucuyla yazılır:
  `{"result": "ok", "uid": "gorev-…"}` ya da `{"result": "hata", "message": "…"}`. Ardından ajanda dosyası
  hemen yeniden yazılır. Aynı uuid yeniden bırakılırsa işlenmez, silinir.
- Bozuk JSON, tanınmayan `schema` ya da `action` da sonucuyla `islendi/`'ye gider.

## Bozulmayanlar

`--ajanda <uid>` (taşınmış duruşmayı da bulur), hatırlatmalar, müvekkil adı seçeneği, dosyanın 0600 izni ve
atomik yazılması, mevcut testler. Değişikliklerin hepsi yalnız Linux'ta; Windows, macOS, Android ve iOS'ta
hiçbir şey değişmez. Folio'nun 1992 testi geçti.
