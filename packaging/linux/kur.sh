#!/bin/sh
# Puts the LifeOS Folio in this folder under ~/.local/share/lifeos-folio and
# into the app menu. No administrator rights; to update, run the kur.sh of
# the newer version the same way.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target="${XDG_DATA_HOME:-$HOME/.local/share}/lifeos-folio"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Kurulum için python3 gerekiyor." >&2
  exit 1
fi
# Copied beside the old one first, then swapped, so a half-copied Folio
# never replaces a working one. A running Folio keeps its open files.
rm -rf "$target.yeni" "$target.eski"
mkdir -p "$target.yeni"
cp -a "$here/." "$target.yeni/"
if [ -d "$target" ]; then mv "$target" "$target.eski"; fi
mv "$target.yeni" "$target"
rm -rf "$target.eski"
python3 "$target/kurulum/install_local.py" "$target/lifeos_folio" >/dev/null
echo "LifeOS Folio kuruldu: $target"
# With ufw on, nothing reaches Folio from the person's phone or the
# office; asked once here, where the installer already is in a terminal.
if [ -t 0 ] && command -v systemctl >/dev/null 2>&1 &&
  [ "$(systemctl is-active ufw 2>/dev/null)" = active ]; then
  printf '%s' "Güvenlik duvarı (ufw) açık. Telefonunuz ve büronuz bu bilgisayara bağlanabilsin mi? [E/h] "
  read -r cevap || cevap=h
  case "$cevap" in
    h | H | hayır | Hayır) ;;
    *)
      # From the local networks only, never all of the internet.
      acik=1
      for ag in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
        sudo ufw allow from "$ag" to any port 47900 proto tcp >/dev/null &&
          sudo ufw allow from "$ag" to any port 5353 proto udp >/dev/null ||
          acik=0
      done
      if [ "$acik" = 1 ]; then
        data="${XDG_DATA_HOME:-$HOME/.local/share}/com.erkanoz.evrak_convert"
        mkdir -p "$data"
        printf '{"kapi":47900}' >"$data/guvenlik_duvari.json"
      fi
      ;;
  esac
fi
echo "Uygulama menüsünden açabilirsiniz."
