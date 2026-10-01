"""Turns capture_pages.sh output into pages.json: for each UDF, the text each
page starts with in UYAP's own editor. page_breaks_test.dart holds Folio's
PDF to it.

    python3 expected_pages.py DIR > pages.json
"""
import base64, json, os, re, sys, zipfile
TOP, PAGE, GAP = 9.13, 842.0, 19.0
def page_of(y): return int((y - TOP) // (PAGE + GAP)) + 1
d = sys.argv[1]
out = {}
for name in sorted(os.listdir(d)):
    if not name.endswith('.udf'): continue
    tsv = os.path.join(d, name[:-4] + '.tsv')
    if not os.path.exists(tsv): continue
    lines = open(tsv).read().splitlines()
    text = base64.b64decode([l for l in lines if l.startswith('text\t')][0][5:]).decode('utf-8')
    rows = [l.split('\t') for l in lines if l.startswith('view\t')]
    # The header's and footer's rows are drawn on every page; only the
    # body's say where a page starts.
    regions = [(int(r[3]), int(r[4])) for r in rows if r[2] in ('O', 'u')]
    rows = [(int(r[3]), int(r[6])) for r in rows if r[2] == 'J'
            and not any(a <= int(r[3]) < b for a, b in regions)]
    # The first row on each page with something written on it: an empty
    # paragraph starting a page draws nothing to compare.
    first = {}
    for off, y in sorted(rows, key=lambda r: (r[1], r[0])):
        p = page_of(y)
        line = text[off:].split('\n')[0]
        first.setdefault(p, '')
        if not first[p] and line.strip():
            first[p] = line.strip()[:24]
    out[name] = [first[p] for p in sorted(first)]
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
