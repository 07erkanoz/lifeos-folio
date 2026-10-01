#!/usr/bin/env python3
"""Verify committed executables/DLLs; --smoke also runs tools on the target OS."""
import argparse
import os
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2] / 'native_tools'

def dll_imports(path):
    data=path.read_bytes();pe=struct.unpack_from('<I',data,0x3c)[0]
    if data[pe:pe+4]!=b'PE\0\0' or struct.unpack_from('<H',data,pe+4)[0]!=0x8664:
        raise RuntimeError(f'{path.name}: not an x64 PE file')
    count=struct.unpack_from('<H',data,pe+6)[0]
    optional=pe+24;size=struct.unpack_from('<H',data,pe+20)[0]
    sections=[]
    for i in range(count):
        at=optional+size+i*40
        virtual_size,rva,raw_size,raw=struct.unpack_from('<IIII',data,at+8)
        sections.append((rva,max(virtual_size,raw_size),raw))
    def offset(rva):
        for start,size,raw in sections:
            if start<=rva<start+size:return raw+rva-start
        raise RuntimeError(f'{path.name}: invalid import address')
    rva=struct.unpack_from('<I',data,optional+120)[0]
    if not rva:return []
    at=offset(rva);names=[]
    while any(data[at:at+20]):
        name=offset(struct.unpack_from('<I',data,at+12)[0])
        names.append(data[name:data.index(0,name)].decode('ascii').lower());at+=20
    return names

def verify(platform):
    root = ROOT / platform
    manifest = json.loads((root / 'checksums.json').read_text())
    # tessdata carries the OCR model, which is checksummed alongside the
    # binaries: a truncated copy would degrade recognition, not fail loudly.
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*')
              if p.is_file() and p.parent.name in ('bin', 'tessdata')}
    if actual != set(manifest):
        raise RuntimeError(f'{platform}: missing or unexpected native tool file')
    for name, expected in manifest.items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'{platform}/{name}: SHA-256 mismatch')
    if platform=='windows-x64':
        bundled={Path(name).name.lower() for name in actual}
        system={'kernel32.dll','advapi32.dll','user32.dll','msvcrt.dll','crypt32.dll','ws2_32.dll'}
        for name in actual:
            if not name.startswith('bin/'): continue
            for dll in dll_imports(root/name):
                if dll not in bundled and dll not in system and not dll.startswith(('api-ms-win-','ext-ms-win-')):
                    raise RuntimeError(f'{name}: missing bundled dependency {dll}')
    print(f'{platform}: {len(manifest)} verified files')

def smoke(platform):
    root = ROOT / platform / 'bin'
    suffix = '.exe' if platform.startswith('windows') else ''
    def run(name, args):
        result = subprocess.run([str(root / (name + suffix)), *map(str, args)], timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0: raise RuntimeError(f'{name}: {result.returncode}: {result.stderr.decode(errors="replace")}')
    with tempfile.TemporaryDirectory(prefix='Folio-Özgür-') as temp:
        temp = Path(temp)
        # One uncompressed grayscale TIFF. No Pillow or Office dependency.
        tags = [(256,4,1,16),(257,4,1,16),(258,3,1,8),(259,3,1,1),
                (262,3,1,1),(273,4,1,122),(277,3,1,1),(278,4,1,16),(279,4,1,256)]
        data = b'II*\0' + struct.pack('<I',8) + struct.pack('<H',len(tags))
        data += b''.join(struct.pack('<HHII',*t) for t in tags) + b'\0'*4 + bytes(range(256))
        source = temp/'Şablon.tif'; source.write_bytes(data)
        out = temp/'Küçük.tif'
        run('tiffcp',['-c','zip:p9',source,out])
        assert out.stat().st_size > 0 and source.read_bytes() == data
        # A valid page whose source and output qpdf must both accept.
        objects = [b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << >> >>']
        pdf = bytearray(b'%PDF-1.4\n'); offsets=[0]
        for i,obj in enumerate(objects,1):
            offsets.append(len(pdf));pdf.extend(f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n')
        xref=len(pdf);pdf.extend(b'xref\n0 4\n0000000000 65535 f \n')
        for offset in offsets[1:]:pdf.extend(f'{offset:010} 00000 n \n'.encode())
        pdf.extend(f'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
        source=temp/'Örnek.pdf';source.write_bytes(pdf);out=temp/'Küçük.pdf'
        run('qpdf',['--object-streams=generate','--recompress-flate',source,out])
        run('qpdf',['--check',out])
        run('jpegtran',['-version'])
        assert source.read_bytes() == pdf
        # Prove the binary runs, finds the model shipped beside it, and can open
        # a file whose path carries Turkish letters. On Windows the last part is
        # what the UTF-8 manifest buys: without it a path like "Müvekkil Özlem"
        # arrives in the legacy code page and the file is simply not found.
        tess = root / ('tesseract' + suffix)
        env = {**os.environ, 'TESSDATA_PREFIX': str(root.parent / 'tessdata')}
        langs = subprocess.run([str(tess), '--list-langs'], timeout=60, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if b'tur' not in langs.stdout:
            raise RuntimeError('tesseract: Turkish model not found beside the binary')
        turkish = temp / 'Müvekkil Özlem Şenoğlu' / 'İhtarname.tif'
        turkish.parent.mkdir()
        turkish.write_bytes(data)
        read = subprocess.run([str(tess), str(turkish), '-', '-l', 'tur', '--psm', '6'],
                              timeout=120, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if read.returncode != 0:
            raise RuntimeError(f'tesseract: Turkish path rejected: '
                               f'{read.stderr.decode(errors="replace")}')
    print(f'{platform}: PDF/TIFF/Unicode-path smoke test passed')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform',choices=['windows-x64','linux-x64','all'])
    parser.add_argument('--smoke',action='store_true')
    args=parser.parse_args()
    for platform in ['windows-x64','linux-x64'] if args.platform=='all' else [args.platform]:
        verify(platform)
        if args.smoke:smoke(platform)
