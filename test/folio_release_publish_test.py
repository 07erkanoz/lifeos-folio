# The lifeos.com.tr side of a release (packaging/server): Windows, Linux and
# Android come in one go, the Mac in a later one, and neither go may undo or
# hold back the other. Signed with a key made here, put in place of Folio's.
#
#   python3 test/folio_release_publish_test.py
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location(
    'folio_release_publish', Path(__file__).resolve().parents[1] / 'packaging/server/folio_release_publish.py'
)
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

NAMES = {
    'windows-x64': 'LifeOS-Folio-{v}-Windows-x64-Setup.exe',
    'linux-x64': 'LifeOS-Folio-{v}-Linux-x64.tar.gz',
    'android': 'LifeOS-Folio-{v}-Android.apk',
    'macos-universal': 'LifeOS-Folio-{v}-macOS.dmg',
}


class PublishTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.keys = tempfile.TemporaryDirectory(prefix='folio-key-')
        cls.key = Path(cls.keys.name) / 'key.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ed25519', '-out', cls.key], check=True)
        der = subprocess.run(
            ['openssl', 'pkey', '-in', cls.key, '-pubout', '-outform', 'DER'], check=True, capture_output=True
        ).stdout
        cls.saved_key = server.PUBLIC_KEY
        server.PUBLIC_KEY = der[-32:]

    @classmethod
    def tearDownClass(cls):
        server.PUBLIC_KEY = cls.saved_key
        cls.keys.cleanup()

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='folio-publish-')
        root = Path(self.work.name)
        self.incoming = root / 'incoming'
        self.site = root / 'site'
        self.incoming.mkdir()
        self.site.mkdir()

    def tearDown(self):
        self.work.cleanup()

    def sign(self, body):
        message = Path(self.work.name) / 'body'
        message.write_bytes(server.canonical(body).encode('utf-8'))
        signature = subprocess.run(
            ['openssl', 'pkeyutl', '-sign', '-inkey', self.key, '-rawin', '-in', message],
            check=True, capture_output=True,
        ).stdout
        return {**body, 'signature': 'ed25519:' + base64.b64encode(signature).decode()}

    def send(self, version, build, platforms, package=True):
        for platform in platforms:
            name = NAMES[platform].format(v=version)
            data = f'{platform} {version}'.encode() * 100
            if package:
                (self.incoming / name).write_bytes(data)
            manifest = self.sign({
                'schema': 1, 'product': 'folio', 'channel': 'stable', 'platform': platform,
                'version': version, 'build': build,
                'url': f'https://lifeos.com.tr/downloads/{name}',
                'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data),
                'notes': {'tr': 'Deneme', 'en': 'Test'}, 'published': '2026-10-16T12:00:00Z',
            })
            (self.incoming / f'{platform}.json').write_text(json.dumps(manifest), 'utf-8')
        (self.incoming / 'READY').touch()

    def published(self, platform):
        path = self.site / 'surum/stable' / f'{platform}.json'
        return json.loads(path.read_text('utf-8'))['version'] if path.exists() else None

    def publish(self):
        try:
            return server.publish(self.incoming, self.site, '')
        finally:
            server.empty(self.incoming)

    def test_the_mac_follows_the_others_in_its_own_go(self):
        self.send('1.7.1', 14, ['windows-x64', 'linux-x64', 'android'])
        self.publish()
        self.assertIsNone(self.published('macos-universal'))
        self.send('1.7.1', 14, ['macos-universal'])
        version, files = self.publish()
        self.assertEqual(version, '1.7.1')
        self.assertEqual(files, ['LifeOS-Folio-1.7.1-macOS.dmg'])
        for platform in NAMES:
            self.assertEqual(self.published(platform), '1.7.1', platform)
            self.assertTrue((self.site / 'downloads' / NAMES[platform].format(v='1.7.1')).exists(), platform)

    def test_a_go_keeps_the_packages_another_go_published(self):
        # The Mac's last package is a month old, then a release comes whose
        # Mac does not follow: what the Mac's manifest names stays.
        self.send('1.7.0', 13, ['macos-universal'])
        self.publish()
        mac = self.site / 'downloads/LifeOS-Folio-1.7.0-macOS.dmg'
        stray = self.site / 'downloads/LifeOS-Folio-1.0.0-Android.apk'
        stray.write_bytes(b'old')
        month_ago = time.time() - 30 * 24 * 3600
        for path in (mac, stray):
            os.utime(path, (month_ago, month_ago))
        self.send('1.7.1', 14, ['windows-x64', 'linux-x64', 'android'])
        self.publish()
        self.assertTrue(mac.exists())
        self.assertEqual(self.published('macos-universal'), '1.7.0')
        # Named by no manifest and a week old: gone.
        self.assertFalse(stray.exists())

    def test_a_manifest_without_its_package_publishes_nothing(self):
        self.send('1.7.1', 14, ['macos-universal'], package=False)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertIsNone(self.published('macos-universal'))

    def test_one_bad_platform_holds_back_the_whole_go(self):
        self.send('1.7.1', 14, ['windows-x64', 'macos-universal'])
        (self.incoming / 'LifeOS-Folio-1.7.1-macOS.dmg').write_bytes(b'not it')
        with self.assertRaises(ValueError):
            self.publish()
        self.assertIsNone(self.published('windows-x64'))

    def test_an_older_or_the_same_build_is_refused(self):
        self.send('1.7.1', 14, ['macos-universal'])
        self.publish()
        self.send('1.7.1', 14, ['macos-universal'])
        with self.assertRaises(ValueError):
            self.publish()

    def test_nothing_sent_is_refused(self):
        (self.incoming / 'READY').touch()
        with self.assertRaises(ValueError):
            self.publish()


if __name__ == '__main__':
    unittest.main()
