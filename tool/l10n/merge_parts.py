#!/usr/bin/env python3
"""Merge lib/l10n/parts/*_{tr,en}.json into lib/l10n/app_{tr,en}.arb (keys must not collide)."""
import json,glob,sys,os
root=sys.argv[1] if len(sys.argv)>1 else '.'
for lang in ('tr','en'):
    arb=os.path.join(root,f'lib/l10n/app_{lang}.arb')
    d=json.load(open(arb,encoding='utf-8'))
    for part in sorted(glob.glob(os.path.join(root,f'lib/l10n/parts/*_{lang}.json'))):
        for k,v in json.load(open(part,encoding='utf-8')).items():
            if k in d and d[k]!=v: sys.exit(f'çakışma: {k} ({part})')
            d[k]=v
    json.dump(d,open(arb,'w',encoding='utf-8'),ensure_ascii=False,indent=2); open(arb,'a').write('\n')
print('birleştirildi')
