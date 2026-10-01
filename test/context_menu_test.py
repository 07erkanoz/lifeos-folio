import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location('folio_context', Path(__file__).resolve().parents[1] / 'packaging/linux/context_menu.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ContextMenuTest(unittest.TestCase):
    def test_safe_arguments_filters_and_idempotent_registration(self):
        with tempfile.TemporaryDirectory(prefix='folio-context-') as tmp:
            root = Path(tmp)
            output = root / 'arguments.json'
            executable = root / 'Folio "Soft" $name'
            executable.write_text('#!/usr/bin/env python3\nimport sys,json\nfrom pathlib import Path\nPath(' + repr(str(output)) + ').write_text(json.dumps(sys.argv[1:]))\n')
            executable.chmod(0o700)
            module.install_context_menus(executable, root / 'data')
            action = root / 'data/nautilus/scripts/Folio ile düzenle'
            stamp = action.stat().st_mtime_ns
            module.install_context_menus(executable, root / 'data')
            self.assertEqual(stamp, action.stat().st_mtime_ns)
            document = root / 'Dilekçe "özel" $x\nyeni.udf'
            document.write_bytes(b'fixture')
            pdf = root / 'metin.pdf'
            pdf.write_bytes(b'%PDF-fixture')
            image = root / 'resim.png'
            image.write_bytes(b'fixture')
            env = dict(os.environ, NAUTILUS_SCRIPT_SELECTED_URIS=document.as_uri()+'\n'+pdf.as_uri()+'\n'+image.as_uri())
            subprocess.run([str(action)], env=env, check=True)
            for _ in range(200):
                if output.exists(): break
                time.sleep(.01)
            self.assertEqual(json.loads(output.read_text()), ['--edit', '--', str(document), str(pdf)])
            kde = root / 'data/kio/servicemenus/lifeos-folio-edit.desktop'
            self.assertNotIn('image/png', kde.read_text())
            self.assertIn('application/pdf', kde.read_text())
            self.assertTrue(os.access(kde, os.X_OK))
            self.assertFalse((root / 'data/applications/mimeapps.list').exists())

if __name__ == '__main__': unittest.main()
