#!/usr/bin/env python3
"""Puts a Folio iPhone build in front of App Review through the App Store
Connect API, so a release tag needs nothing done by hand.

    asc_release.py next-build
        Prints the build number the next upload should carry: one above the
        highest Apple has seen for the app, so two uploads never clash.

    asc_release.py submit VERSION BUILD NOTES_JSON
        Waits for that build to be processed, opens (or renames) the App
        Store version, writes the Turkish "what's new" from the release
        notes, attaches the build and submits it for review.

The key comes from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file).
Only the standard library and the openssl command are used.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP = '6820659076'
API = 'https://api.appstoreconnect.apple.com'

# Versions App Store Connect still lets us change.
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED',
            'METADATA_REJECTED', 'INVALID_BINARY'}
# Versions already with Apple: nothing more to do for them.
SUBMITTED = {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE',
             'PENDING_APPLE_RELEASE', 'PROCESSING_FOR_APP_STORE', 'READY_FOR_SALE'}


def b64u(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def der_to_raw(sig):
    """An ECDSA signature from openssl (DER) as JWT's r||s."""
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7f)
    parts = []
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        parts.append(sig[i + 2:i + 2 + n].lstrip(b'\0').rjust(32, b'\0'))
        i += 2 + n
    return parts[0] + parts[1]


def token():
    key_id, issuer = os.environ['ASC_KEY_ID'], os.environ['ASC_ISSUER_ID']
    head = b64u(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    now = int(time.time())
    body = b64u(json.dumps({'iss': issuer, 'iat': now, 'exp': now + 900,
                            'aud': 'appstoreconnect-v1'}).encode())
    sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', os.environ['ASC_KEY_PATH']],
                         input=f'{head}.{body}'.encode(), capture_output=True, check=True).stdout
    return f'{head}.{body}.{b64u(der_to_raw(sig))}'


def api(method, path, data=None, fail=True):
    body = None if data is None else json.dumps(data).encode()
    for attempt in range(6):
        req = urllib.request.Request(API + path, method=method, data=body)
        req.add_header('Authorization', 'Bearer ' + token())
        req.add_header('Content-Type', 'application/json')
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.loads(r.read() or b'{}')
        except urllib.error.HTTPError as e:
            msg = f'{method} {path}: HTTP {e.code} {e.read().decode()[:1500]}'
            if fail:
                sys.exit(msg)
            print(msg)
            return None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            print('Bağlantı hatası, yeniden deneniyor:', e)
            time.sleep(10 * (attempt + 1))
    sys.exit(f'{method} {path}: bağlanılamadı')


def next_build():
    builds = api('GET', f'/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=50')['data']
    print(max([int(b['attributes']['version']) for b in builds if b['attributes']['version'].isdigit()],
              default=0) + 1)


def wait_for_build(version, number):
    query = (f'/v1/builds?filter[app]={APP}&filter[version]={number}'
             f'&filter[preReleaseVersion.version]={version}')
    for _ in range(120):  # an hour
        found = api('GET', query)['data']
        if found:
            build = found[0]
            state = build['attributes']['processingState']
            if state == 'VALID':
                return build['id']
            if state in ('FAILED', 'INVALID'):
                sys.exit(f'Derleme {version} ({number}) Apple tarafından işlenemedi: {state}')
        time.sleep(30)
    sys.exit(f'Derleme {version} ({number}) bir saatte işlenmedi.')


def the_version(version):
    versions = api('GET', f'/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=50')['data']
    for v in versions:
        if v['attributes']['versionString'] == version:
            return v
    busy = [v for v in versions if v['attributes']['appStoreState'] in
            ('WAITING_FOR_REVIEW', 'IN_REVIEW')]
    if busy:
        sys.exit(f'{busy[0]["attributes"]["versionString"]} hâlâ incelemede; '
                 f'{version} ondan sonra gönderilebilir.')
    for v in versions:
        if v['attributes']['appStoreState'] in EDITABLE:
            api('PATCH', f'/v1/appStoreVersions/{v["id"]}', {'data': {
                'type': 'appStoreVersions', 'id': v['id'],
                'attributes': {'versionString': version}}})
            return api('GET', f'/v1/appStoreVersions/{v["id"]}')['data']
    return api('POST', '/v1/appStoreVersions', {'data': {
        'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': version,
                       'releaseType': 'AFTER_APPROVAL'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})['data']


def submit(version, number, notes_path):
    whats_new = json.load(open(notes_path, encoding='utf-8'))['tr'].strip()[:4000]
    build = wait_for_build(version, number)
    print(f'Derleme {version} ({number}) işlendi.')
    v = the_version(version)
    state = v['attributes']['appStoreState']
    if state in SUBMITTED:
        print(f'{version} zaten Apple’da ({state}); yapılacak bir şey yok.')
        return
    vid = v['id']
    for loc in api('GET', f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations')['data']:
        if loc['attributes']['locale'] == 'tr':
            # The very first version has no "what's new"; Apple refuses it.
            api('PATCH', f'/v1/appStoreVersionLocalizations/{loc["id"]}', {'data': {
                'type': 'appStoreVersionLocalizations', 'id': loc['id'],
                'attributes': {'whatsNew': whats_new}}}, fail=False)
    print('“Bu sürümdeki yenilikler” yazıldı.')
    api('PATCH', f'/v1/appStoreVersions/{vid}/relationships/build',
        {'data': {'type': 'builds', 'id': build}})
    print('Derleme sürüme bağlandı.')

    # One open submission at a time: reuse one left unsent by an earlier run.
    open_ones = api('GET', f'/v1/reviewSubmissions?filter[app]={APP}'
                           f'&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW')['data']
    if open_ones:
        sub = open_ones[0]['id']
    else:
        sub = api('POST', '/v1/reviewSubmissions', {'data': {
            'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})['data']['id']
    items = api('GET', f'/v1/reviewSubmissions/{sub}/items?include=appStoreVersion')['data']
    if not any(((i.get('relationships') or {}).get('appStoreVersion') or {}).get('data', {}).get('id') == vid
               for i in items):
        api('POST', '/v1/reviewSubmissionItems', {'data': {
            'type': 'reviewSubmissionItems',
            'relationships': {
                'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sub}},
                'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}}}})
    api('PATCH', f'/v1/reviewSubmissions/{sub}', {'data': {
        'type': 'reviewSubmissions', 'id': sub, 'attributes': {'submitted': True}}})
    print(f'{version} incelemeye gönderildi.')


if __name__ == '__main__':
    if sys.argv[1:2] == ['next-build']:
        next_build()
    elif sys.argv[1:2] == ['submit'] and len(sys.argv) == 5:
        submit(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)
