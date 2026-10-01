# Folio native document tools

These **committed binaries** ship in every Windows/Linux build. No download,
Office/LibreOffice installation or PATH configuration happens on a user's PC.
Keep the application directory intact: CMake copies the matching platform folder
to `tools/` alongside `lifeos_folio`, including all helper DLLs and notices.
It verifies SHA-256 checksums and fails the build if any file is missing/changed.
The application uses absolute paths; it never picks a tool from the user's PATH.
Android builds do not include these desktop tools.

| Tool | Version | Windows x64 files | Linux x64 |
|---|---|---|---|
| qpdf | 12.4.1 | qpdf.exe, libjpeg-62.dll | qpdf |
| LibTIFF | 4.7.2 | tiffcp.exe, libtiff-6.dll, libjpeg-62.dll, libzlib.dll | tiffcp |
| libjpeg-turbo | 3.1.2 | jpegtran.exe, libjpeg-62.dll | jpegtran |
| zlib | 1.3.1 | libzlib.dll (and static code in qpdf) | static code |
| Tesseract | 5.5.3 | tesseract.exe | tesseract |
| Leptonica | 1.87.0 | static code in tesseract | static code in tesseract |
| libpng | 1.6.50 | static code in tesseract | static code in tesseract |

Tesseract reads scanned documents so they can be searched. Unlike the tools
above it links everything statically on both targets and ships no DLLs of its
own: it is built against a second, all-static prefix so it does not depend on
the DLL set the other tools share. `tesseract.exe` carries the same
`activeCodePage=UTF-8` manifest, so a path like `Müvekkil Özlem\İhtarname.tif`
reaches it intact — `verify.py --smoke` reads a file from exactly such a folder
on both platforms rather than assuming it works.

Two Turkish models ship. `tur` is `tessdata_fast` and reads a page in 3.4 s, which is what indexing a whole archive can afford. `tur_best` is `tessdata_best`, 6.0 s a page, used when a reader asks for one document and waits for it — on a notarised page it kept all ten phrases that must survive intact where the quick model lost one.

The model in `tessdata/` comes from upstream `tessdata_fast` and is
pinned and checksummed like the binaries; it is Apache-2.0, same as Tesseract.
The fast model was chosen over the 18 MB standard one after both were compared
on rendered Turkish legal text covering every letter Turkish adds to the
alphabet, and they produced identical output.

Rebuilding does not need a local MinGW: the **Paketlenen belge araçlarını
yeniden derle** workflow runs `build_tools.py` on a runner for either target and
publishes the result as a prerelease, which the app's test packages moved to as
well because Actions artifact storage is a small shared quota. It never pushes —
a tool that ships inside the app is reviewed before it lands.

Windows tools target Windows 10 1903+ / Windows 11 x64, use the OS's UCRT,
and need no separate GCC/MSVC runtime installation. TIFF/JPEG executables carry
an UTF-8 active-code-page manifest; qpdf uses its Unicode entry point. All
non-OS DLL imports are present in `windows-x64/bin`.

Linux binaries are built by the rebuild workflow on its Ubuntu runner and need
glibc 2.38 or newer; `readelf -V` on each one says what it actually asks for.
Build them there rather than on a rolling distribution: a tesseract built on
Arch once required glibc 2.43, which runs on Arch alone and silently disabled
OCR everywhere else, because the app finds the binary, fails to start it and
reports no readable text. An older baseline is the safe direction — glibc keeps
older binaries working on newer systems, so what the runner produces also runs
on Arch, while the reverse does not hold. Only the system C/math libraries and
dynamic loader remain external; zlib/JPEG/C++ runtimes are linked into the
helper programs. Distributions below the baseline require rebuilding these
tools there, alongside the Flutter/GTK runtime requirements.

TIFF codecs: uncompressed, PackBits, LZW, CCITT/Fax, Deflate and JPEG (including
old-JPEG reading). Optional JBIG/LERC/LZMA/Zstd/WebP codecs are not enabled.
Unknown codecs produce an error and leave the original file intact. TIFF pixel
integrity does not promise preservation of every private tag or SubIFD.

qpdf uses its upstream native crypto provider. Folio uses qpdf for stream
inspection/repacking, not electronic signature verification or signing.

## Updating / verifying

- Sources and their exact download hashes: `sources.lock.json`.
- Notices: `licenses/`. These tools keep their own licenses; Folio's application
  license does not replace them. qpdf: Apache-2.0; LibTIFF: its permissive license;
  libjpeg-turbo: IJG/BSD/zlib terms; zlib: zlib license. Compiler support code uses
  the GCC Runtime Library Exception; MinGW notices are included.
- Maintainer rebuild: `python packaging/native/build_tools.py linux --work /tmp/folio-tools`.
- Windows cross build: same command with `windows --toolchain /absolute/toolchain.cmake
  --windres x86_64-w64-mingw32-windres --strip x86_64-w64-mingw32-strip`.
  The toolchain must set Windows/x64, C/C++/RC compilers and include the work
  directory's `prefix` in `CMAKE_FIND_ROOT_PATH`. GCC/MinGW-w64 16.2.0/14.0.0 were used.
- Verify tracked files: `python packaging/native/verify.py all`.
- Run on the respective OS: `python packaging/native/verify.py windows-x64 --smoke`
  or `linux-x64 --smoke`. This tests actual PDF/TIFF operations with Turkish paths.
- Windows manual CI verifies the binaries and smoke test before packaging; no
  network download of helper components is required during ordinary builds.

The Windows binaries were additionally exercised under Wine on Linux with
multi-page TIFF and JPEG pixel comparisons, PDF structure checks and Turkish
paths. This is not a substitute for testing the full Flutter app on Windows.
