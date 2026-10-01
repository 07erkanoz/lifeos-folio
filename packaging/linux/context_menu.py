#!/usr/bin/env python3
"""Install per-user file-manager actions without changing default applications."""
import argparse
import json
import os
from pathlib import Path
import tempfile

PREVIEW = 'pdf udf docx xlsx odt txt md markdown html htm csv tsv json xml log png jpg jpeg gif webp bmp tif tiff svg'.split()
EDIT = 'pdf udf docx xlsx odt txt md markdown html htm csv tsv json xml log'.split()
MIMES = 'application/pdf;application/x-uyap-udf;application/udf;application/x-udf;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.oasis.opendocument.text;text/plain;text/html;text/markdown;text/csv;text/tab-separated-values;application/json;application/xml;text/xml;image/png;image/jpeg;image/gif;image/webp;image/bmp;image/tiff;image/svg+xml;'
EDIT_MIMES = ';'.join(m for m in MIMES.split(';') if m and not m.startswith('image/')) + ';'


def quote_exec(value):
    return '"' + value.replace('\\', '\\\\\\\\').replace('"', '\\\\"').replace('`', '\\\\`').replace('$', '\\\\$').replace('%', '%%') + '"'


def publish(target, text, executable=False):
    data = text.encode('utf-8')
    if target.exists() and target.read_bytes() == data:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.folio-action-', dir=target.parent) as staging:
        pending = Path(staging) / 'payload'
        with pending.open('wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        pending.chmod(0o700 if executable else 0o600)
        pending.replace(target)


def install_context_menus(executable, base):
    executable, base = str(executable), Path(base)
    for verb, label, extensions, mimes in [
        ('preview', 'Folio ile önizle', PREVIEW, MIMES),
        ('edit', 'Folio ile düzenle', EDIT, EDIT_MIMES),
    ]:
        # URI lists preserve embedded newlines in names. Never evaluate shell text.
        script = '''#!/usr/bin/env python3
import os, sys, subprocess
from pathlib import Path
from urllib.parse import urlsplit, unquote
executable = EXECUTABLE
extensions = EXTENSIONS
paths = sys.argv[1:]
if not paths:
    uris = os.environ.get('NAUTILUS_SCRIPT_SELECTED_URIS') or os.environ.get('NEMO_SCRIPT_SELECTED_URIS')
    if uris:
        paths = [unquote(u.path) for line in uris.splitlines() if (u := urlsplit(line)).scheme == 'file' and u.netloc in ('', 'localhost')]
    else:
        paths = (os.environ.get('NAUTILUS_SCRIPT_SELECTED_FILE_PATHS') or os.environ.get('NEMO_SCRIPT_SELECTED_FILE_PATHS') or '').splitlines()
selected = [str(Path(path).absolute()) for path in paths if Path(path).is_file() and Path(path).suffix.lower().lstrip('.') in extensions]
if selected:
    subprocess.Popen([executable, VERB, '--', *selected], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
'''.replace('EXECUTABLE', json.dumps(executable)).replace('EXTENSIONS', repr(extensions)).replace('VERB', repr('--' + verb))
        for manager in ['nautilus', 'nemo']:
            publish(base / manager / 'scripts' / label, script, executable=True)
        desktop = f'''[Desktop Entry]
Type=Service
MimeType={mimes}
Actions=Folio;
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
X-KDE-Priority=TopLevel

[Desktop Action Folio]
Name={label}
Icon=com.erkanoz.evrak_convert
Exec={quote_exec(executable)} --{verb} -- %F
'''
        publish(base / 'kio/servicemenus' / f'lifeos-folio-{verb}.desktop', desktop, executable=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--data-home', type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error('Geçerli bir Folio çalıştırıcısı gerekli.')
    base = args.data_home or Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    install_context_menus(executable, base)
    print('GNOME/Nemo: sağ tuş → Betikler. KDE: sağ tuş → Folio ile önizle/düzenle.')


if __name__ == '__main__':
    main()
