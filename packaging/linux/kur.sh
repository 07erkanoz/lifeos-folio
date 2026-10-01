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
echo "Uygulama menüsünden açabilirsiniz."
