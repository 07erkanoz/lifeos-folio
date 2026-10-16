#!/usr/bin/env bash
# Sends a release's packages and signed manifests to lifeos.com.tr, then
# waits until the site publishes them:
#
#   DEPLOY_KEY=… KNOWN_HOSTS=… bash tool/release/send_to_site.sh \
#     <folder> <version> <platform>…
#
# The key can only drop files into the server's incoming folder; the
# server publishes them only if their signatures check out
# (packaging/server). READY goes last: it is what starts the server's
# check. The release workflow sends Windows, Linux and Android in one go
# and the Mac in another, once Apple has notarized it.
set -euo pipefail
folder="$1"
version="$2"
shift 2

work="${RUNNER_TEMP:-$(mktemp -d)}"
install -m 600 /dev/null "$work/deploy_key"
printf '%s\n' "$DEPLOY_KEY" > "$work/deploy_key"
printf '%s\n' "$KNOWN_HOSTS" > "$work/known_hosts"
ssh="ssh -i $work/deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$work/known_hosts"
rsync -rt -e "$ssh" "$folder/" folio-release@sbyazilim.info:
touch "$work/READY"
rsync -t -e "$ssh" "$work/READY" folio-release@sbyazilim.info:READY
rm -f "$work/deploy_key"

for platform in "$@"; do
  seen=''
  for attempt in $(seq 1 30); do
    seen="$(curl -fsS -H 'Cache-Control: no-cache' "https://lifeos.com.tr/surum/stable/$platform.json" | jq -r .version || true)"
    [ "$seen" = "$version" ] && break
    sleep 10
  done
  if [ "$seen" != "$version" ]; then
    echo "::error::lifeos.com.tr $platform için $version göstermiyor (${seen:-yok})."
    exit 1
  fi
  manifest="$(curl -fsS -H 'Cache-Control: no-cache' "https://lifeos.com.tr/surum/stable/$platform.json")"
  url="$(jq -r .url <<< "$manifest")"
  size="$(jq -r .size <<< "$manifest")"
  # A file the site does not have still answers 200, with the site's own
  # page: the package is there only if its size is the manifest's.
  served="$(curl -fsSI "$url" | tr -d '\r' | sed -nE 's/^[Cc]ontent-[Ll]ength: *([0-9]+)$/\1/p' | tail -1)"
  if [ "$served" != "$size" ]; then
    echo "::error::$url $size bayt olmalı, site ${served:-?} bayt veriyor: paket yerinde değil."
    exit 1
  fi
  echo "$platform: $version yayında, $url"
done
