#!/usr/bin/env bash
# Folio built here (build/linux/x64/release/bundle) gets the desktop entry
# and icon the package installs: on Wayland the window's icon comes from
# the entry named after its application id, not from the window, and a
# Folio built from the repository showed a blank icon (22 Kasım 2026).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"
data="${XDG_DATA_HOME:-$HOME/.local/share}"

install_one() {
  local id="$1" binary="$2" icon="$3"
  [[ -x "$bundle/$binary" ]] || return 0
  for size in 512 256 128 64 48 32; do
    local dir="$data/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$dir"
    if [[ $size == 512 ]] || ! command -v magick >/dev/null; then
      [[ $size == 512 ]] && cp "$root/assets/branding/$icon" "$dir/$id.png"
    else
      magick "$root/assets/branding/$icon" -resize "${size}x${size}" "$dir/$id.png"
    fi
  done
  mkdir -p "$data/applications"
  sed -e "s|^Exec=[^ ]*|Exec=\"$bundle/$binary\"|" \
    "$root/packaging/linux/$id.desktop" >"$data/applications/$id.desktop"
}

install_one com.erkanoz.evrak_convert lifeos_folio lifeos_folio.png
install_one com.erkanoz.lifeos_editor lifeos_editor lifeos_editor.png
install_one com.erkanoz.lifeos_ofis lifeos_ofis lifeos_ofis.png

command -v update-desktop-database >/dev/null &&
  update-desktop-database "$data/applications" || true
command -v gtk-update-icon-cache >/dev/null &&
  gtk-update-icon-cache -q -t "$data/icons/hicolor" || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
echo "Folio'nun masaüstü kaydı ve simgesi kuruldu: $data/applications"
