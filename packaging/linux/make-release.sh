#!/usr/bin/env bash
# Packs the built Linux bundle as artifacts/LifeOS-Folio-<version>-Linux-x64.tar.gz:
# one LifeOS-Folio folder holding the bundle, kur.sh, and the scripts kur.sh
# uses to add Folio to the app menu.
set -euo pipefail
cd "$(dirname "$0")/../.."
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+[[:space:]]*$/\1/p' pubspec.yaml)"
test -n "$version" || { echo "pubspec.yaml sürümü okunamadı." >&2; exit 1; }
bundle=build/linux/x64/release/bundle
test -x "$bundle/lifeos_folio" || { echo "Linux bundle derlenmemiş." >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/LifeOS-Folio"
mkdir -p "$root/kurulum"
cp -a "$bundle/." "$root/"
cp packaging/linux/install_local.py packaging/linux/context_menu.py \
  packaging/linux/*.desktop "$root/kurulum/"
install -m 755 packaging/linux/kur.sh "$root/kur.sh"
mkdir -p artifacts
out="artifacts/LifeOS-Folio-$version-Linux-x64.tar.gz"
tar -C "$stage" --owner=0 --group=0 --numeric-owner -czf "$out" LifeOS-Folio
echo "$out"
