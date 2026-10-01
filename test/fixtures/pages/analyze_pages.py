"""Reads what capture_pages.sh wrote and says, for each paragraph (and
table row), on which page each of its rows landed. Page n spans
[9.13 + (n - 1) * 861, + 842) in UYAP's unzoomed view."""
import sys
TOP, PAGE, GAP = 9.13, 842.0, 19.0
def page_of(y): return int((y - TOP) // (PAGE + GAP)) + 1
for path in sys.argv[1:]:
    views = [l.split('\t') for l in open(path).read().splitlines() if l.startswith('view')]
    print('==', path.split('/')[-1])
    rows = [v for v in views if v[2] == 'J']
    last = None
    out = []
    for v in rows:
        start, y, h = int(v[3]), int(v[6]), int(v[8])
        p = page_of(y)
        out.append((start, y, h, p))
    # report around page changes
    for i, (s, y, h, p) in enumerate(out):
        if i and p != out[i - 1][2 + 1]:
            a = out[i - 1]
            print(f'  page {a[3]}->{p}: last row y={a[1]} h={a[2]} bottom={a[1]+a[2]} (page bottom {TOP+(a[3]-1)*(PAGE+GAP)+PAGE-70.87:.1f}), next row y={y} (content top {TOP+(p-1)*(PAGE+GAP)+70.87:.1f}) offsets {a[0]}->{s}')
    print('  rows', len(out), 'pages', out[-1][3])
