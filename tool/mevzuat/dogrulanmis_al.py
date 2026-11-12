#!/usr/bin/env python3
"""assets/mevzuat/dogrulanmis.json: Bedesten'in geride kaldığı maddelerin
resmî metinden kesilmiş hâli. Kaynak, banaozel'in doğrulanmış kesimi
(server/mevzuat_dogrulanmis): her dilim resmî metnin birebir alt dizgisidir.
Yalnız hedef maddeler alınır. Kullanım: python3 tool/mevzuat/dogrulanmis_al.py
[banaozel/server/mevzuat_dogrulanmis]"""
import json, os, sys

kaynak = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/projeler/banaozel/server/mevzuat_dogrulanmis')
manifest = json.load(open(os.path.join(kaynak, 'manifest.json')))
out = {'kesim_tarihi': manifest['kesim_tarihi'], 'kanunlar': {}}
for no, k in manifest['kanunlar'].items():
    dilimler = {d['etiket']: d for d in json.load(open(os.path.join(kaynak, f'{no}.json')))}
    maddeler = {}
    for etiket in k['hedef_maddeler']:
        d = dilimler[etiket]
        assert d['metin'].strip(), etiket
        maddeler[etiket] = {'baslik': d.get('baslik') or '', 'metin': d['metin']}
    out['kanunlar'][no] = {
        'kaynak': k['kaynak'],
        'resmi': k.get('kaynak_resmi', True) is not False,
        'maddeler': maddeler,
    }
hedef = 'assets/mevzuat/dogrulanmis.json'
with open(hedef, 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print(hedef, sum(len(k['maddeler']) for k in out['kanunlar'].values()), 'madde')
