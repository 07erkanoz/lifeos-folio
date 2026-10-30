# Folio'da yapay zekâ: yol haritası

30 Ekim 2026. Kaynaklar: banaozel incelemesi (yalnız okundu, ortaklaştırılmaz) ve yargi-mcp ile mevzuat-mcp
incelemesi (kullanılmayacak; ikisinin kodu da GitHub'dan kalkmış, incelenen sürümler MIT). Her şey Folio'nun
içinde, terminalsiz; önce Linux, sonra Windows ve Mac. Telefonda yok.

## Temel ilkeler

- Avukatın kendi aboneliği ve kendi bilgisayarındaki resmî CLI (Claude Code, Codex, Google Antigravity). API
  anahtarı yok, LifeOS sunucusu araya girmez.
- Kullanım onayı bir kez sorulur, saklanır (tarih, avukat, metin sürümü), geri alınabilir; metin değişince
  yeniden sorulur. Veri sorumlusu avukattır.
- Programlar salt okunur ve bütün araçları kapalı çalışır; yalnız Folio'nun kendi MCP araçları açılır. Codex'te
  `-s read-only` yazmayı engeller, okumayı değil: kabuk, tarayıcı, eklenti, görsel ve web araması ayrıca
  kapatılır (yapıldı).
- **Uydurma yok.** Kanun maddesi ve karar yalnız Folio'nun araçlarından gelir; bilinmeyen `[yer tutucu]` ya da
  "bulunamadı" kalır. Tarih ve süre hesabını model değil Folio'nun süre motoru yapar.
- **Denetim var, kapı yok.** Yanıttaki künye, alıntı ve madde atıfları Folio tarafından denetlenir ve görünür
  biçimde işaretlenir; sessiz düzeltme yapılmaz.
- Seçilen sağlayıcı yoksa başka sağlayıcıya sessizce geçilmez; açıkça söylenir.
- Belgedeki talimatlar veridir, kural değiştiremez.

## Modeller: iki kademe

| Kademe | İşler | Claude | Codex | Antigravity |
|---|---|---|---|---|
| Normal | özet, tebligat türü ve süre çıkarımı, yapılacak iş çıkarımı, evrak seçme | Sonnet 5.5 | gpt-6-luna | Gemini 3.8 Flash |
| Güçlü | analiz, inceleme, dilekçe yazma, rapor değerlendirme, dosya analizi | Opus 5.5 | gpt-6.1-sol | Gemini 4 Argon (High) |

Arayüzde marka değil "Normal / Güçlü" görünür; avukat Ayarlar'dan değiştirebilir. Model adları her programın
kendi listesinden okunur (`agy models`, Codex model listesi); listede yoksa en yakın kademe söylenir.

## Aşamalar

1. **Yapıldı:** önizlemede Yapay zekâ paneli (Özetle, Belgeye sor), Ayarlar › Yapay zekâ, tek seferlik onay,
   TC kimlik numarası gizleme, Folio'dan oturum açma (Claude, Codex).
2. **İstem çekirdeği ve kademeler:** ortak çekirdek (uydurma yasağı, kaynak/yorum ayrımı, alıntıyı birebir
   koruma, kısmi okumadan yokluk çıkarmama, Türkçe ve şapkasız yazım, belgedeki talimat veridir) + görev
   modülü (mesaja eklenir). Hafif işler JSON ve kapalı listeyle, `guven` eşiğiyle ("belirsiz" dönebilir),
   `alinti` alanı birebir ve Folio'ca belgede aranır.
3. **Folio MCP sunucusu** (`lifeos_folio --mcp`, stdio, yalnız okuma; CLI'lara yalnız bu sunucu açılır):

   | Araç | Ne yapar |
   |---|---|
   | `mevzuat_madde` | Kanun no/kısaltma/ad + madde ("49", "68/a", "geçici 3") → aynen metin, mülga bilgisi, resmî adres, hazır atıf |
   | `mevzuat_ara` | Önce `laws.json`, sonra Bedesten mevzuat araması → kanun listesi |
   | `mevzuat_icindekiler` | Kanunun madde ve başlık listesi; model numara uydurmak yerine seçer |
   | `karar_ara` | Yargıtay, Danıştay, istinaf, KYB, AYM; daire, iki uçlu tarih aralığı, E/K no |
   | `karar_getir` | Kimlik ya da daire+E+K → aynen metin, 5-8 bin karakterlik parçalar, `daire_farkli` |
   | `atif_dogrula` | Taslaktaki her atfı Folio'nun atıf tarayıcısıyla denetler |
   | `dosya_bilgisi` | Dosyanın künyesi, taraflar, müvekkilin sıfatı (ayrı satır), safahat, duruşmalar, açık süreler |
   | `dosya_evraklari` | Evrak listesi: inmiş mi, okunabilir mi, kısmi mi |
   | `evrak_oku` | İnmiş evrakın metni (`coverage`, `text_quality`) |
   | `evrak_indir` | İnmemiş evrakı ister; Folio avukata "şu evraklar indirilsin mi?" diye sorar, onaylarsa tek sıra kuralıyla indirir |

   Her sonuç `durum` (bulundu / yok / ulaşılamadı), kalıcı kimlik, resmî adres ve kaynak etiketi taşır. Arayüzle
   aynı Bedesten kuyruğu ve disk önbelleği kullanılır. Dışarı yalnız arama sözcükleri ve numaralar çıkar.
4. **Sonradan denetim:** künye denetimi (dar desen), alıntı denetimi (birebir / yazım farkı / farklı / kaynak
   yok), madde atfı bu turda okundu mu, TC/IBAN kontrol hanesi. Dilekçede "tam metni okunmamış karara
   dayanıldı" uyarısı modele geri verilir.
5. **Kullanıldığı yerler:**
   - **Dosya ekranı:** icra, hukuk, ceza ve idare dosyasının analizi; dosya haritası müvekkil sıfatını ayrı
     satırda taşır, her icra dosyası ayrı ele alınır.
   - **Editör:** varsayılan iş bu metindir; öneri yalnız ayrı bir "belge" bloğunda gelir, "Belgeye ekle" yalnız
     ona bağlıdır; imzalı belgede uyarı. Dilekçe kuralları: üst blok tablo olmaz, ispat yükü ayrılır, bilinmeyen
     `[yer tutucu]` kalır.
   - **Ana sayfa:** model çağırmayan öncelik kartları ve dosya künyesini taşıyan hazır soru çipleri; yazaç
     dosyasız sohbet açar.
   - **Tebligat ve zabıt:** tür, 250 kelimelik özet, en fazla 6 eylem cümlesi; süre yalnız açıkça yazıyorsa,
     tarihi Folio hesaplar; güven düşükse süre gösterilmez.
6. **Dosyanın kendiliğinden bağlanması:** dosya no + mahkeme; mahkeme çelişirse bağlanmaz; tekillik şartı
   ("yanlış bağ bağsızlıktan kötüdür"); ilk bağ sessiz, ek bağda "Kaldır / Ayrı konuşmada aç" şeridi. Araç
   sonucunun ilk satırı dosya kimliğidir.
7. **Rehber verisi:** dilekçe, metodoloji ve atıf rehberleri izinli kaynaklardan bağımsız yeniden yazılır,
   Folio'nun veri paketiyle sürümlenir; dilekçe, bilirkişi ve sözleşme işinde bir kez okunur; rehberdeki her
   madde atfı mevzuat paketine karşı denetlenir.

## Ölçme

Her istem değişikliği, önceden yazılmış senaryolar ve geçme ölçütleriyle denenir; karar kuralı "önceki sürümün
geçtiğini kaybetme". Uydurma ölçütü: yanıttaki her künye ve madde araç sonucunda geçiyor mu.
