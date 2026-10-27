#!/bin/sh
# Puts the LifeOS Ofis in this folder under ~/.local/share/lifeos-ofis, into
# the app menu, and makes it what UDF, Word, ODT, RTF, PDF and .imz files
# open in. No administrator rights; to update, run the kur.sh of the newer
# version the same way.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target="${XDG_DATA_HOME:-$HOME/.local/share}/lifeos-ofis"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Kurulum için python3 gerekiyor." >&2
  exit 1
fi
# Copied beside the old one first, then swapped, so a half-copied Ofis
# never replaces a working one. A running Ofis keeps its open files.
rm -rf "$target.yeni" "$target.eski"
mkdir -p "$target.yeni"
cp -a "$here/." "$target.yeni/"
if [ -d "$target" ]; then mv "$target" "$target.eski"; fi
mv "$target.yeni" "$target"
rm -rf "$target.eski"
python3 "$target/kurulum/install_local.py" --ofis "$target/lifeos_ofis" >/dev/null
echo "LifeOS Ofis kuruldu: $target"
echo "Uygulama menüsünden açabilirsiniz."
