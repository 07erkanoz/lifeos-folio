#!/usr/bin/env python3
"""Puts a LifeOS Folio release that GitHub sent onto lifeos.com.tr.

The release workflow copies the packages and their signed manifests into
the incoming folder over a restricted SSH key, then a READY file;
folio-release.path starts this then. For each platform it checks the
manifest's Ed25519 signature with Folio's public key, that it is newer than
what is published, and the file's size and SHA-256. Only then does the file
go under /downloads/ and the manifest under /surum/stable/ — files first, so
a manifest never names a file that is not there yet. Anything that does not
check out publishes nothing. The incoming folder is emptied either way.

The SSH key can only drop files; the signature, which only the release
workflow can make, is what decides whether they are published.

Standard library and the openssl command only.
"""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse

PLATFORMS = ('windows-x64', 'linux-x64', 'android')
# Same key as UpdateManifest.publicKey in the app.
PUBLIC_KEY = base64.b64decode('uo8uTbTSKeMNBtitM6hL25KFShLiMnlZKA6gbTPcxgY=')
HOST = 'lifeos.com.tr'
# Old packages stay this long after a newer one replaces them, so a
# download already under way still finishes.
KEEP_OLD = 7 * 24 * 3600


def canonical(value):
    """The bytes the signature covers: the app's canonical JSON."""
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def verify_signature(manifest):
    signature = manifest.get('signature', '')
    if not isinstance(signature, str) or not signature.startswith('ed25519:'):
        raise ValueError('imzasız sürüm bilgisi')
    body = {k: v for k, v in manifest.items() if k != 'signature'}
    der = bytes.fromhex('302a300506032b6570032100') + PUBLIC_KEY
    with tempfile.TemporaryDirectory() as work:
        work = pathlib.Path(work)
        (work / 'key.pem').write_text(
            '-----BEGIN PUBLIC KEY-----\n' + base64.b64encode(der).decode() + '\n-----END PUBLIC KEY-----\n'
        )
        (work / 'body').write_bytes(canonical(body).encode('utf-8'))
        (work / 'sig').write_bytes(base64.b64decode(signature[len('ed25519:'):]))
        result = subprocess.run(
            ['openssl', 'pkeyutl', '-verify', '-pubin', '-inkey', work / 'key.pem',
             '-rawin', '-in', work / 'body', '-sigfile', work / 'sig'],
            capture_output=True, text=True,
        )
    if result.returncode != 0:
        raise ValueError('sürüm bilgisinin imzası doğrulanamadı')


def check_manifest(manifest, platform):
    """The package's file name, once the manifest is Folio's and for
    [platform]."""
    verify_signature(manifest)
    if (manifest.get('schema'), manifest.get('product'), manifest.get('channel'), manifest.get('platform')) != (
        1, 'folio', 'stable', platform
    ):
        raise ValueError(f'{platform}: sürüm bilgisi bu platform için değil')
    url = urllib.parse.urlsplit(manifest['url'])
    name = urllib.parse.unquote(url.path.removeprefix('/downloads/'))
    if (url.scheme != 'https' or url.netloc != HOST or not url.path.startswith('/downloads/')
            or not name or '/' in name or name.startswith('.')):
        raise ValueError(f'{platform}: tanınmayan adres {manifest["url"]}')
    return name


def regular(path):
    """[path] as bytes, refusing anything but a plain file."""
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'{path.name} düz bir dosya değil')
    return path.read_bytes()


def published_build(site, platform):
    try:
        return json.loads((site / 'surum/stable' / f'{platform}.json').read_text('utf-8'))['build']
    except (OSError, ValueError, KeyError):
        return 0


def install(data, target, owner):
    """Writes beside the target, then renames over it, so a reader never
    gets half a file."""
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_name(f'.{target.name}.yeni')
    pending.write_bytes(data)
    os.chmod(pending, 0o644)
    if owner:
        shutil.chown(pending, *owner.split(':'))
    os.replace(pending, target)


def publish(incoming, site, owner):
    ready = []
    # Everything is checked before anything is published.
    for platform in PLATFORMS:
        manifest_bytes = regular(incoming / f'{platform}.json')
        manifest = json.loads(manifest_bytes.decode('utf-8'))
        name = check_manifest(manifest, platform)
        if manifest['build'] <= published_build(site, platform):
            raise ValueError(f'{platform}: {manifest["version"]} yayımlanandan yeni değil')
        data = regular(incoming / name)
        if len(data) != manifest['size'] or hashlib.sha256(data).hexdigest() != manifest['sha256']:
            raise ValueError(f'{name} sürüm bilgisiyle uyuşmuyor')
        ready.append((platform, name, manifest_bytes, manifest['version']))

    downloads = site / 'downloads'
    for _, name, _, _ in ready:
        install((incoming / name).read_bytes(), downloads / name, owner)
    for platform, _, manifest_bytes, _ in ready:
        install(manifest_bytes, site / 'surum/stable' / f'{platform}.json', owner)
    for directory in (downloads, site / 'surum', site / 'surum/stable'):
        os.chmod(directory, 0o755)
        if owner:
            shutil.chown(directory, *owner.split(':'))

    current = {name for _, name, _, _ in ready}
    for old in downloads.glob('LifeOS-Folio-*'):
        if old.name not in current and time.time() - old.stat().st_mtime > KEEP_OLD:
            old.unlink()
    return ready[0][3], sorted(current)


def empty(incoming):
    for entry in incoming.iterdir():
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--incoming', type=pathlib.Path, default=pathlib.Path('/var/lib/folio-release/incoming'))
    parser.add_argument('--site', type=pathlib.Path, default=pathlib.Path('/var/www/vhosts/lifeos.com.tr/httpdocs'))
    parser.add_argument('--owner', default='lifeos:psaserv', help='user:group for published files; empty to leave as is')
    args = parser.parse_args()
    if not (args.incoming / 'READY').exists():
        return
    try:
        version, files = publish(args.incoming, args.site, args.owner)
        print(f'LifeOS Folio {version} yayında: {", ".join(files)}')
    except (ValueError, KeyError, OSError) as error:
        sys.exit(f'Folio sürümü yayımlanmadı: {error}')
    finally:
        empty(args.incoming)


if __name__ == '__main__':
    main()
