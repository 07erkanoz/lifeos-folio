#!/usr/bin/env python3
"""Join native_tools/macos-arm64 and macos-x86_64 into macos-universal.

Each tool becomes one universal binary, so the same app runs them on an Apple
Silicon Mac and on an Intel one. The OCR models are the same files in both
halves and are copied once. Runs on a Mac: lipo and codesign are Apple's.
"""
import hashlib, json, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'native_tools'
arm, intel, out = ROOT / 'macos-arm64', ROOT / 'macos-x86_64', ROOT / 'macos-universal'
if out.exists():
    shutil.rmtree(out)
(out / 'bin').mkdir(parents=True)
for tool in sorted((arm / 'bin').iterdir()):
    dest = out / 'bin' / tool.name
    subprocess.run(['lipo', '-create', tool, intel / 'bin' / tool.name, '-output', dest], check=True)
    # lipo writes a new file; each half's signature does not carry over.
    subprocess.run(['codesign', '--force', '--sign', '-', dest], check=True)
    subprocess.run(['lipo', '-verify_arch', 'arm64', 'x86_64', dest], check=True)
shutil.copytree(arm / 'tessdata', out / 'tessdata')
hashes = {f.relative_to(out).as_posix(): hashlib.sha256(f.read_bytes()).hexdigest()
          for f in sorted(p for p in out.rglob('*') if p.is_file())}
(out / 'checksums.json').write_text(json.dumps(hashes, indent=2) + '\n')
shutil.rmtree(arm)
shutil.rmtree(intel)
print('Merged:', out)
