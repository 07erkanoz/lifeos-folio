# Folio canlı paylaşım aktarıcısı

Başka bir büroyla, aynı ağda olmadan canlı paylaşılan belge bu servisten geçer
(`canli.lifeos.com.tr`). Servis iki Folio'yu aynı odada buluşturur ve birinin
söylediğini diğerine olduğu gibi iletir. Belge iki Folio arasında davet
kodundan üretilen anahtarla şifrelidir; kod servise hiç gelmez, servis içeriği
açamaz ve hiçbir şey kaydetmez. Protokol `lib/services/live/live_remote.dart`
içinde anlatılır.

## Sunucudaki kurulum (avukathesap.com, LifeOS paneli)

- Program: `/home/erkanoz/projeler/folio-canli/folio-canli`, `10.0.0.1:3021`
  adresini dinler (yalnız Docker ağı; Caddy `host.docker.internal` ile ulaşır).
- Servis: `lifeos-app add` ile kuruldu, adı `lifeos-folio-canli`. Bellek ve
  yetki sınırları `/etc/systemd/system/lifeos-folio-canli.service.d/sinir.conf`
  dosyasında.
- Güvenlik duvarı: `ufw allow in on docker0 from 10.0.0.0/24 to 10.0.0.1 port
  3021 proto tcp`.
- DNS: `lifeos-dns point lifeos.com.tr --name canli` (yalnız DNS, Cloudflare
  vekili kapalı).
- Caddy: `lifeos-site add --domains canli.lifeos.com.tr --mode proxy --target
  host.docker.internal:3021` (panelin `.env` dosyasındaki `CADDY_*` değerleriyle).

## Güncelleme

```bash
dart compile exe tool/canli_relay/main.dart -o build/canli_relay/folio-canli
scp build/canli_relay/folio-canli root@avukathesap.com:/home/erkanoz/projeler/folio-canli/folio-canli.yeni
ssh root@avukathesap.com 'cd /home/erkanoz/projeler/folio-canli && mv folio-canli.yeni folio-canli && chown erkanoz:erkanoz folio-canli && systemctl restart lifeos-folio-canli'
```

Yeniden başlatma, o an süren uzaktan paylaşımları keser. Denetim:
`curl https://canli.lifeos.com.tr/saglik` → `ok`.
