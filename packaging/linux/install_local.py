#!/usr/bin/env python3
"""Register a built LifeOS bundle in this user's Linux app menu (no defaults)."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from context_menu import install_context_menus

APP_ID = 'com.erkanoz.evrak_convert'


def quote_exec(value):
    # Desktop Entry Exec grammar, not shell quoting.
    return '"' + value.replace('\\', '\\\\\\\\').replace('"', '\\\\"').replace('`', '\\\\`').replace('$', '\\\\$').replace('%', '%%') + '"'


def replace_if_changed(target, data):
    if target.exists() and target.read_bytes() == data:
        return False
    with tempfile.TemporaryDirectory(prefix='.folio-install-', dir=target.parent) as staging:
        pending = Path(staging) / 'payload'
        with pending.open('wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        pending.replace(target)
    return True


EDITOR_ID = 'com.erkanoz.lifeos_editor'


def install_editor(executable, applications, icons):
    """LifeOS Editör, beside Folio in the same bundle, in the menu of its own."""
    icon = executable.parent / 'data/flutter_assets/assets/branding/lifeos_editor.png'
    if not executable.is_file() or not os.access(executable, os.X_OK) or not icon.is_file():
        return
    replace_if_changed(icons / f'{EDITOR_ID}.png', icon.read_bytes())
    template = (Path(__file__).parent / f'{EDITOR_ID}.desktop').read_text()
    desktop = template.replace('Exec=lifeos_editor %F', f'Exec={quote_exec(str(executable))} %F')
    entry = applications / f'{EDITOR_ID}.desktop'
    replace_if_changed(entry, desktop.encode('utf-8'))
    print(entry)


def refresh_icon_cache(theme):
    """GTK trusts a theme's icon-theme.cache over the files beside it, and
    judges it stale by the theme folder's time alone, which an icon written
    into a size folder does not change. A cache another program wrote before
    LifeOS Editör's icon was added hid that icon from the menu. Rebuilt when
    there is one; removed when there is no tool to rebuild it, so the folders
    are read instead."""
    cache = theme / 'icon-theme.cache'
    if not cache.exists():
        return
    tool = shutil.which('gtk-update-icon-cache')
    if tool:
        result = subprocess.run([tool, '-f', '-t', '-q', str(theme)], capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return
    cache.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    icon = executable.parent / 'data/flutter_assets/assets/branding/lifeos_folio.png'
    if not executable.is_file() or not os.access(executable, os.X_OK) or not icon.is_file():
        parser.error('Geçerli Linux bundle çalıştırıcısı ve ikon bulunamadı.')
    base = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    applications = base / 'applications'
    icons = base / 'icons/hicolor/256x256/apps'
    applications.mkdir(parents=True, exist_ok=True)
    icons.mkdir(parents=True, exist_ok=True)
    target_icon = icons / f'{APP_ID}.png'
    replace_if_changed(target_icon, icon.read_bytes())
    template = (Path(__file__).parent / f'{APP_ID}.desktop').read_text()
    desktop = template.replace('Exec=lifeos_folio %F', f'Exec={quote_exec(str(executable))} %F')
    entry = applications / f'{APP_ID}.desktop'
    changed = replace_if_changed(entry, desktop.encode('utf-8'))
    if changed and shutil.which('update-desktop-database'):
        result = subprocess.run(['update-desktop-database', str(applications)], capture_output=True, text=True, timeout=15)
        if result.returncode:
            print(f'update-desktop-database: {result.stderr.strip()}')
    install_editor(executable.parent / 'lifeos_editor', applications, icons)
    refresh_icon_cache(icons.parent.parent)
    install_context_menus(executable, base)
    print(entry)
    print(target_icon)


if __name__ == '__main__':
    main()
