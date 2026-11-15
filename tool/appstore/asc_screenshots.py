#!/usr/bin/env python3
"""Puts a folder's App Store pictures on an iOS version in place of the
ones there: iphone-NN.jpg to the iPhone's set, ipad-NN.jpg to the iPad's,
in the order of NN.

  ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… \
    python3 tool/appstore/asc_screenshots.py <version> <folder>

The pictures come from tool/appstore/store_images.py.
"""
import glob
import hashlib
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_release as a  # noqa: E402

SETS = {'iphone': 'APP_IPHONE_67', 'ipad': 'APP_IPAD_PRO_3GEN_129'}


def upload(set_id, path):
    data = open(path, 'rb').read()
    made = a.api('POST', '/v1/appScreenshots', {'data': {
        'type': 'appScreenshots',
        'attributes': {'fileName': os.path.basename(path), 'fileSize': len(data)},
        'relationships': {'appScreenshotSet': {
            'data': {'type': 'appScreenshotSets', 'id': set_id}}}}})['data']
    for op in made['attributes']['uploadOperations']:
        part = data[op['offset']:op['offset'] + op['length']]
        req = urllib.request.Request(op['url'], data=part, method=op['method'])
        for h in op.get('requestHeaders') or []:
            req.add_header(h['name'], h['value'])
        with urllib.request.urlopen(req, timeout=120) as r:
            r.read()
    a.api('PATCH', f'/v1/appScreenshots/{made["id"]}', {'data': {
        'type': 'appScreenshots', 'id': made['id'],
        'attributes': {'uploaded': True,
                       'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
    return made['id']


def main():
    version, folder = sys.argv[1:3]
    v = a.the_version(version)
    loc = [l for l in a.api('GET', f'/v1/appStoreVersions/{v["id"]}/appStoreVersionLocalizations')['data']
           if l['attributes']['locale'] == 'tr'][0]
    sets = {s['attributes']['screenshotDisplayType']: s['id'] for s in
            a.api('GET', f'/v1/appStoreVersionLocalizations/{loc["id"]}/appScreenshotSets')['data']}
    for prefix, kind in SETS.items():
        files = sorted(glob.glob(os.path.join(folder, f'{prefix}-*.jpg')))
        if not files:
            continue
        set_id = sets.get(kind) or a.api('POST', '/v1/appScreenshotSets', {'data': {
            'type': 'appScreenshotSets', 'attributes': {'screenshotDisplayType': kind},
            'relationships': {'appStoreVersionLocalization': {
                'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id']}}}}})['data']['id']
        old = a.api('GET', f'/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50')['data']
        for s in old:
            a.api('DELETE', f'/v1/appScreenshots/{s["id"]}')
        print(f'{kind}: {len(old)} eski görsel silindi')
        ids = [upload(set_id, f) for f in files]
        a.api('PATCH', f'/v1/appScreenshotSets/{set_id}/relationships/appScreenshots',
              {'data': [{'type': 'appScreenshots', 'id': i} for i in ids]})
        print(f'{kind}: {len(ids)} görsel yüklendi')
    # Apple checks each picture after the upload.
    for _ in range(40):
        states = []
        allsets = a.api('GET', f'/v1/appStoreVersionLocalizations/{loc["id"]}/appScreenshotSets')['data']
        for s in allsets:
            for sh in a.api('GET', f'/v1/appScreenshotSets/{s["id"]}/appScreenshots?limit=50')['data']:
                states.append((sh['attributes'].get('assetDeliveryState') or {}).get('state'))
        if all(st == 'COMPLETE' for st in states):
            print('Apple görselleri işledi:', len(states))
            return
        if any(st == 'FAILED' for st in states):
            sys.exit(f'Apple bir görseli kabul etmedi: {states}')
        time.sleep(15)
    print('Görseller hâlâ işleniyor:', states)


if __name__ == '__main__':
    main()
