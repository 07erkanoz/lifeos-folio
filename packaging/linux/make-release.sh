#!/usr/bin/env bash
# Packs the built Linux bundle as artifacts/LifeOS-Folio-<version>.<build>-Linux-x64.tar.gz
# (a new build of one version is a file of its own):
# one LifeOS-Folio folder holding the bundle, kur.sh, and the scripts kur.sh
# uses to add Folio to the app menu. With `ofis`, LifeOS Ofis from the same
# bundle instead, as artifacts/LifeOS-Ofis-<version>.<build>-Linux-x64.tar.gz: its
# own program only, without Folio's, the Editör's and the e-Devlet window's,
# and the kur.sh that installs it as the documents' default.
set -euo pipefail
cd "$(dirname "$0")/../.."
product="${1:-folio}"
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+[[:space:]]*$/\1/p' pubspec.yaml)"
test -n "$version" || { echo "pubspec.yaml sürümü okunamadı." >&2; exit 1; }
build="$(sed -nE 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)[[:space:]]*$/\1/p' pubspec.yaml)"
bundle=build/linux/x64/release/bundle
case "$product" in
  folio) name=LifeOS-Folio program=lifeos_folio installer=kur.sh ;;
  ofis) name=LifeOS-Ofis program=lifeos_ofis installer=kur-ofis.sh ;;
  *) echo "Bilinmeyen paket: $product (folio ya da ofis)" >&2; exit 64 ;;
esac
test -x "$bundle/$program" || { echo "Linux bundle derlenmemiş." >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/$name"
mkdir -p "$root/kurulum"
cp -a "$bundle/." "$root/"
if [ "$product" = ofis ]; then
  rm -f "$root/lifeos_folio" "$root/lifeos_editor" "$root/folio-edevlet"
fi
cp packaging/linux/install_local.py packaging/linux/context_menu.py \
  packaging/linux/*.desktop packaging/linux/lifeos-evrakci.xml \
  packaging/linux/lifeos-imz.xml "$root/kurulum/"
install -m 755 "packaging/linux/$installer" "$root/kur.sh"
mkdir -p artifacts
out="artifacts/$name-$version.$build-Linux-x64.tar.gz"
tar -C "$stage" --owner=0 --group=0 --numeric-owner -czf "$out" "$name"
echo "$out"
