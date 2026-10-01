#!/usr/bin/env python3
"""Maintainer-only rebuild of pinned sources. Ordinary Flutter builds are offline.
Linux host: CMake/Ninja/GCC; Windows target additionally needs a MinGW toolchain.
macOS host: CMake/Ninja/Xcode clang, one architecture per run (--arch);
merge_macos.py joins the two into native_tools/macos-universal.
After rebuilding run verify.py, smoke tests and review the new binary checksums.
"""
import argparse, hashlib, json, os, shutil, subprocess, tarfile, urllib.request
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('target',choices=['linux','windows','macos'])
p.add_argument('--arch',choices=['arm64','x86_64'],default='arm64')
p.add_argument('--work',type=Path,required=True)
p.add_argument('--toolchain',type=Path)
p.add_argument('--windres',default='x86_64-w64-mingw32-windres')
p.add_argument('--strip',default='strip')
a=p.parse_args();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
if a.target=='windows' and not a.toolchain:p.error('--toolchain is required for Windows cross builds')
source=work/'source';source.mkdir(exist_ok=True)
data_files={}
for entry in json.loads((REPO/'native_tools/sources.lock.json').read_text()):
    archive=work/entry['file']
    if not archive.exists():urllib.request.urlretrieve(entry['url'],archive)
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest!=entry['sha256']:
        # A truncated answer or a rate-limit page is cached like a real archive
        # and then fails every later run with the same line, so drop it and let
        # a retry fetch the file again. The size and digest say which happened:
        # a few kilobytes is the host refusing, a full-length mismatch is not.
        size=archive.stat().st_size;archive.unlink()
        raise RuntimeError(f'Wrong source hash: {entry["file"]} — {size} bytes, sha256 {digest}')
    # Trained models ship as-is; only real archives are unpacked.
    if entry.get('kind')=='file':data_files[entry['file']]=archive;continue
    with tarfile.open(archive) as tar:tar.extractall(source,filter='data')
# These build-only fixes select the cross compiler and case-correct Windows lib.
qpdf=source/'qpdf-12.4.1/CMakeLists.txt'
s=qpdf.read_text().replace('CMAKE_REQUIRED_LIBRARIES Advapi32','CMAKE_REQUIRED_LIBRARIES advapi32').replace('COMMAND gcc --print-file-name=CRT_glob.o','COMMAND ${CMAKE_C_COMPILER} --print-file-name=CRT_glob.o')
qpdf.write_text(s)
# Tesseract asks the linker for "Ws2_32". Windows does not care about the case,
# but MinGW on a Linux host looks for a file named libws2_32.a and finds none.
tess_lists=source/'tesseract-5.5.3/CMakeLists.txt'
tess_lists.write_text(tess_lists.read_text().replace('set(LIB_Ws2_32 Ws2_32)','set(LIB_Ws2_32 ws2_32)'))
prefix=work/'prefix'
def run(args):subprocess.run(list(map(str,args)),check=True)
def build(name,folder,options,targets):
    out=work/name
    cmd=['cmake','-S',source/folder,'-B',out,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',f'-DCMAKE_INSTALL_PREFIX={prefix}','-DCMAKE_POSITION_INDEPENDENT_CODE=ON']
    if a.toolchain:cmd.append(f'-DCMAKE_TOOLCHAIN_FILE={a.toolchain.resolve()}')
    run(cmd+apple+options)
    run(['cmake','--build',out,'--target',*targets,'-j','6'])
    return out
windows=a.target=='windows'
mac=a.target=='macos'
# Apple's clang links libc++ and libSystem dynamically and always will; both
# are part of every macOS, so the tools stay self-contained without these.
link='' if mac else '-static-libgcc -static-libstdc++'
# One architecture per run, for the oldest macOS the app itself supports. The
# runner's Homebrew holds libpng, libtiff and the rest: kept out of sight, so
# nothing links against a library a lawyer's Mac does not have.
apple=[f'-DCMAKE_OSX_ARCHITECTURES={a.arch}','-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0',
       '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local','-DCMAKE_FIND_FRAMEWORK=NEVER',
       # Ninja itself comes from Homebrew, which the line above hides.
       f'-DCMAKE_MAKE_PROGRAM={shutil.which("ninja")}'] if mac else []
manifest=[]
if windows:
    rc=work/'utf8.rc';rc.write_text(f'1 24 "{(REPO/"packaging/native/utf8.manifest").as_posix()}"\n')
    obj=work/'utf8.o';run([a.windres,rc,obj]);manifest=[f'-DCMAKE_EXE_LINKER_FLAGS={obj} {link}']
build('zlib','zlib-1.3.1',[],['install'])
# zlib installs a shared copy beside the static one; leave it and every later
# find_package picks the .so, which would make the tools non-portable.
if not windows:
    for stale in [*prefix.glob('lib/libz.so*'),*prefix.glob('lib/libz*.dylib')]:stale.unlink()
jpeg=build('jpeg','libjpeg-turbo-3.1.2',[f'-DENABLE_SHARED={"ON" if windows else "OFF"}',f'-DENABLE_STATIC={"OFF" if windows else "ON"}','-DWITH_TURBOJPEG=OFF','-DWITH_SIMD=OFF',*manifest],['install'])
# CMake's GNUInstallDirs may use lib or lib64; discover the installed library.
def library(name):return next(prefix.rglob(name))
z=library('libzlib.dll.a' if windows else 'libz.a')
j=library('libjpeg.dll.a' if windows else 'libjpeg.a')
tiff=build('tiff','tiff-4.7.2',[f'-DBUILD_SHARED_LIBS={"ON" if windows else "OFF"}','-Dtiff-tests=OFF','-Dtiff-docs=OFF','-Dtiff-contrib=OFF','-Dtiff-cxx=OFF','-Dwebp=OFF','-Dzstd=OFF','-Dlzma=OFF','-Djbig=OFF','-Dlerc=OFF','-Dlibdeflate=OFF','-Djpeg-prefer-standard=ON',
  # jpeglib.h declares the 12-bit entry points even when the library is built
  # without them, so libtiff compiles tif_jpeg_12.c and the link fails on
  # jpeg12_*. Tell it what this libjpeg actually has.
  '-Djpeg12=OFF','-DHAVE_JPEGTURBO_DUAL_MODE_12=0',f'-DJPEG_LIBRARY_RELEASE={j}',f'-DJPEG_LIBRARY={j}',f'-DJPEG_INCLUDE_DIR={prefix}/include',f'-DZLIB_LIBRARY={z}',f'-DZLIB_INCLUDE_DIR={prefix}/include',*(manifest if windows else [f'-DCMAKE_EXE_LINKER_FLAGS={link}'])],['tiffcp'])
# Use qpdf's supported native crypto provider; compression doesn't require an
# external SSL installation. Disable pkg-config to prevent host library leakage.
q=build('qpdf','qpdf-12.4.1',['-DBUILD_SHARED_LIBS=OFF','-DBUILD_STATIC_LIBS=ON','-DBUILD_DOC=OFF','-DBUILD_TESTING=OFF','-DINSTALL_EXAMPLES=OFF','-DUSE_IMPLICIT_CRYPTO=OFF','-DREQUIRE_CRYPTO_NATIVE=ON','-DPKG_CONFIG_EXECUTABLE=/usr/bin/false',f'-DZLIB_H_PATH={prefix}/include',f'-DZLIB_LIB_PATH={library("libzlibstatic.a") if windows else z}',f'-DLIBJPEG_H_PATH={prefix}/include',f'-DLIBJPEG_LIB_PATH={j}',f'-DCMAKE_EXE_LINKER_FLAGS={"-static " if windows else ""}{link}'],['qpdf'])
# OCR chain. It gets its own prefix built entirely static, on both targets: the
# document tools above deliberately ship Windows DLLs, and mixing the two would
# make tesseract depend on a matrix of DLLs instead of standing alone. Building
# the codecs twice costs maintainer time only.
ocr=work/'ocr';ocr.mkdir(exist_ok=True)
def obuild(name,folder,options,targets):
    out=work/f'ocr-{name}'
    cmd=['cmake','-S',source/folder,'-B',out,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',
         f'-DCMAKE_INSTALL_PREFIX={ocr}','-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
         f'-DCMAKE_PREFIX_PATH={ocr}']
    if a.toolchain:cmd.append(f'-DCMAKE_TOOLCHAIN_FILE={a.toolchain.resolve()}')
    run(cmd+apple+options)
    run(['cmake','--build',out,'--target',*targets,'-j','6'])
    return out
def olib(name):return next(ocr.rglob(name))
obuild('zlib','zlib-1.3.1',[],['install'])
# zlib installs a shared copy beside the static one; left in place, every later
# find_package prefers the .so/.dll and the tool stops being self-contained.
for stale in list(ocr.glob('lib/libz.so*'))+list(ocr.glob('lib/libz*.dylib'))+list(ocr.glob('bin/*zlib*.dll'))+list(ocr.glob('lib/libzlib.dll.a')):
    stale.unlink()
oz=olib('libzlibstatic.a' if windows else 'libz.a')
obuild('jpeg','libjpeg-turbo-3.1.2',['-DENABLE_SHARED=OFF','-DENABLE_STATIC=ON','-DWITH_TURBOJPEG=OFF','-DWITH_SIMD=OFF'],['install'])
oj=olib('libjpeg.a')
obuild('png','libpng-1.6.50',['-DPNG_SHARED=OFF','-DPNG_STATIC=ON','-DPNG_TESTS=OFF','-DPNG_TOOLS=OFF','-DPNG_FRAMEWORK=OFF',f'-DZLIB_LIBRARY={oz}',f'-DZLIB_INCLUDE_DIR={ocr}/include'],['install'])
on=olib('libpng.a')
obuild('tiff','tiff-4.7.2',['-DBUILD_SHARED_LIBS=OFF','-Dtiff-tests=OFF','-Dtiff-docs=OFF','-Dtiff-contrib=OFF','-Dtiff-cxx=OFF','-Dwebp=OFF','-Dzstd=OFF','-Dlzma=OFF','-Djbig=OFF','-Dlerc=OFF','-Dlibdeflate=OFF','-Djpeg-prefer-standard=ON',
  # jpeglib.h declares the 12-bit entry points even when the library is built
  # without them, so libtiff compiles tif_jpeg_12.c and the link dies on jpeg12_*.
  '-Djpeg12=OFF','-DHAVE_JPEGTURBO_DUAL_MODE_12=0',
  f'-DJPEG_LIBRARY_RELEASE={oj}',f'-DJPEG_LIBRARY={oj}',f'-DJPEG_INCLUDE_DIR={ocr}/include',
  f'-DZLIB_LIBRARY_RELEASE={oz}',f'-DZLIB_LIBRARY={oz}',f'-DZLIB_INCLUDE_DIR={ocr}/include'],['install'])
ot=olib('libtiff.a')
# Tiff_DIR: Leptonica looks for TIFF in CONFIG mode, so without this the host's
# /usr/lib/cmake/tiff wins over the copy built here.
obuild('leptonica','leptonica-1.87.0',['-DBUILD_SHARED_LIBS=OFF','-DSW_BUILD=OFF','-DBUILD_PROG=OFF','-DENABLE_ZLIB=ON','-DENABLE_PNG=ON','-DENABLE_TIFF=ON','-DENABLE_JPEG=ON','-DENABLE_WEBP=OFF','-DENABLE_OPENJPEG=OFF','-DENABLE_GIF=OFF',
  f'-DTiff_DIR={ocr}/lib/cmake/tiff',
  f'-DZLIB_LIBRARY_RELEASE={oz}',f'-DZLIB_LIBRARY={oz}',f'-DZLIB_INCLUDE_DIR={ocr}/include',
  f'-DJPEG_LIBRARY_RELEASE={oj}',f'-DJPEG_LIBRARY={oj}',f'-DJPEG_INCLUDE_DIR={ocr}/include',
  f'-DPNG_LIBRARY_RELEASE={on}',f'-DPNG_LIBRARY={on}',f'-DPNG_PNG_INCLUDE_DIR={ocr}/include'],['install'])
# libtiff exports ZLIB::ZLIB and JPEG::JPEG transitively while Leptonica's config
# never declares them, so Tesseract's own try_compile probe dies on an unknown
# target. Bind both to the static libraries just built.
config=ocr/'lib/cmake/leptonica/LeptonicaConfig.cmake'
text=config.read_text()
if 'Folio build fix' not in text:
    config.write_text('# Folio build fix: declare the targets libtiff exports transitively.\n'
        +''.join(f'if(NOT TARGET {t}::{t})\n  add_library({t}::{t} UNKNOWN IMPORTED)\n'
                 f'  set_target_properties({t}::{t} PROPERTIES IMPORTED_LOCATION "{p}"\n'
                 f'    INTERFACE_INCLUDE_DIRECTORIES "{ocr}/include")\nendif()\n'
                 for t,p in (('ZLIB',oz),('JPEG',oj)))+text)
# -static on Windows so tesseract.exe carries libstdc++ and winpthreads itself,
# and the UTF-8 manifest so Turkish file and folder names survive the command
# line the app builds. Without the manifest a path like "Müvekkil Özlem" reaches
# the tool in the legacy code page and the file is simply not found.
# Tesseract probes Leptonica's TIFF support by running a test program, which a
# Linux host cannot do with a Windows binary: CMake stops and asks for the answer
# up front. Leptonica is built above with ENABLE_TIFF against the libtiff in this
# same prefix, so the run it cannot perform would succeed. Left unanswered the
# cross build fails outright, and suppressing it would be worse than failing:
# tesseract quietly drops TIFF, which is what most scanned archives are.
# Tesseract links TIFF into the executable under WIN32 only, and there
# find_package(TIFF) fails beneath the cross toolchain. The pkg-config fallback
# that takes over reports the library as a bare "tiff" and drops the directory
# it lives in, so the link ends in -ltiff with no -L. Pin it by path, as zlib,
# JPEG and PNG already are. Windows only: the Linux executable never links it.
wintiff=['-DLEPT_TIFF_RESULT=0',f'-DTIFF_LIBRARY_RELEASE={ot}',f'-DTIFF_LIBRARY={ot}',
         f'-DTIFF_INCLUDE_DIR={ocr}/include'] if windows else []
# The Intel half of the Mac build is made on an Apple Silicon runner, where the
# same probe would run an x86_64 program; answer it the same way.
if mac:wintiff=['-DLEPT_TIFF_RESULT=0']
tess=build('tesseract','tesseract-5.5.3',['-DBUILD_SHARED_LIBS=OFF','-DSW_BUILD=OFF','-DBUILD_TRAINING_TOOLS=OFF','-DBUILD_TESTS=OFF','-DDISABLE_CURL=ON','-DDISABLE_ARCHIVE=ON','-DGRAPHICS_DISABLED=ON','-DUSE_SYSTEM_ICU=OFF','-DOPENMP_BUILD=OFF',*wintiff,
  f'-DCMAKE_PREFIX_PATH={ocr}',f'-DLeptonica_DIR={ocr}/lib/cmake/leptonica',
  f'-DCMAKE_EXE_LINKER_FLAGS={f"-static {obj} " if windows else ""}{link}'],['tesseract'])
out=REPO/'native_tools'/(f'macos-{a.arch}' if mac else f'{a.target}-x64');(out/'bin').mkdir(parents=True,exist_ok=True)
files=[q/('qpdf/qpdf.exe' if windows else 'qpdf/qpdf'),tiff/('tools/tiffcp.exe' if windows else 'tools/tiffcp'),jpeg/('jpegtran.exe' if windows else 'jpegtran-static')]
files.append(tess/('bin/tesseract.exe' if windows else 'bin/tesseract'))
(out/'tessdata').mkdir(exist_ok=True)
shutil.copy2(data_files['tur.traineddata'],out/'tessdata/tur.traineddata')
# Two models on purpose: the quick one for indexing a whole archive, the
# accurate one for a document the user asked for and is waiting on.
shutil.copy2(data_files['tur_best.traineddata'],out/'tessdata/tur_best.traineddata')
if windows:files += [tiff/'libtiff/libtiff-6.dll',prefix/'bin/libjpeg-62.dll',prefix/'bin/libzlib.dll']
for f in files:
    dest=out/'bin'/('jpegtran' if f.name=='jpegtran-static' else f.name)
    shutil.copy2(f,dest);run([a.strip,dest])
    # Stripping undoes the linker's own signature, and an Apple Silicon Mac
    # refuses to run an unsigned binary; an ad-hoc one is enough to run.
    if mac:run(['codesign','--force','--sign','-',dest])
# The model is as load-bearing as the binary: a truncated copy would quietly
# degrade recognition instead of failing, so it is checksummed too.
hashes={f.relative_to(out).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()
        for f in sorted(p for p in out.rglob('*') if p.is_file() and p.parent.name in ('bin','tessdata'))}
(out/'checksums.json').write_text(json.dumps(hashes,indent=2)+'\n')
cmake='# Generated from the committed native binaries. Verification is offline.\n'
for name,sha in hashes.items():
    cmake+=f'file(SHA256 "${{FOLIO_TOOLS}}/{name}" FOLIO_TOOL_HASH)\nif(NOT FOLIO_TOOL_HASH STREQUAL "{sha}")\n  message(FATAL_ERROR "Native tool checksum mismatch: {name}")\nendif()\n'
(out/'checksums.cmake').write_text(cmake)
print('Rebuilt:',out,'— run pixel-integrity and smoke tests before committing.')
