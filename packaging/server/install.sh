#!/bin/sh
# Sets up, on the lifeos.com.tr server, the user GitHub's release workflow
# sends Folio's packages as and the job that publishes them. Run as root
# with the public half of the workflow's SSH key as the only argument:
#   sh install.sh "ssh-ed25519 AAAA… folio-release-github"
# Safe to run again; it replaces the key.
set -eu
key="$1"
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

id folio-release >/dev/null 2>&1 || useradd --system --home-dir /var/lib/folio-release/home \
  --no-create-home --shell /bin/sh folio-release
install -d -m 755 -o root -g root /var/lib/folio-release /var/lib/folio-release/home
install -d -m 755 -o root -g root /var/lib/folio-release/home/.ssh
install -d -m 700 -o folio-release -g folio-release /var/lib/folio-release/incoming
# The key can do one thing: write files into the incoming folder.
printf 'command="/usr/bin/rrsync -wo /var/lib/folio-release/incoming",restrict %s\n' "$key" \
  > /var/lib/folio-release/home/.ssh/authorized_keys
chmod 644 /var/lib/folio-release/home/.ssh/authorized_keys

install -d -m 755 /usr/local/lib/folio-release
install -m 755 "$here/folio_release_publish.py" /usr/local/lib/folio-release/
install -m 644 "$here/folio-release.service" "$here/folio-release.path" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now folio-release.path
