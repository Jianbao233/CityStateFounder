"""Offline package/real plugin ABI checks; never launches Civ6 or Steam."""
import ctypes
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('shared_package', ROOT/'tools/package_shared_loader.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

class SharedPackageTests(unittest.TestCase):
    def test_real_plugin_rejects_incompatible_context_before_game_access(self):
        module = ctypes.CDLL(str(ROOT/'build/shared_native/CityStateFounder.dll'))
        module.OnLoad.argtypes = [ctypes.c_void_p]
        module.OnLoad.restype = ctypes.c_int
        class Context(ctypes.Structure):
            _fields_ = [('size',ctypes.c_uint32),('api',ctypes.c_uint32),('query',ctypes.c_void_p)]
        self.assertEqual(module.OnLoad(None),0)
        for context in [Context(0,1,None),Context(ctypes.sizeof(Context),2,None),Context(ctypes.sizeof(Context),1,None)]:
            self.assertEqual(module.OnLoad(ctypes.byref(context)),0)
        module.Civ6PluginKind.restype = ctypes.c_uint64
        self.assertEqual(module.Civ6PluginKind(),(1<<32)|2)
        module.OnUnload()

    def test_real_package_has_exact_registered_native_set_and_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)/'CityStateFounder'
            package.package(out)
            root = ET.parse(out/'CityStateFounder.modinfo').getroot()
            self.assertEqual(root.get('version'),'112')
            natives = {n.text.strip() for n in root.findall('./Files/File') if n.text.endswith('.dll')}
            self.assertEqual(natives,{'Binaries/Win64/GameCore_XP2_Shell_FinalRelease.dll',
                 'Binaries/Win64/Civ6DllLoader.winmm.runtime.dll',
                 'Binaries/Win64/Plugins/GameCore/CityStateFounder.dll'})
            manifest = json.loads((out/'BUILD_MANIFEST.json').read_text(encoding='utf-8'))
            self.assertEqual(manifest['runtime'],'WINMM/format2/1.0.6')
            self.assertEqual(manifest['compatibility']['runtime_game'],'NOT_RUN')
            self.assertEqual(manifest['game_build'],26407122)
            for entry in manifest['files']:
                self.assertEqual(package.sha((out/entry['path']).read_bytes()),entry['sha256'])
            db=sqlite3.connect(':memory:')
            db.executescript("CREATE TABLE GameCores(GameCore TEXT,PackageId TEXT,DllPrefix TEXT);INSERT INTO GameCores VALUES('Base','base','a'),('Expansion1','xp1','b'),('Expansion2','xp2','c');")
            db.executescript((out/'Config/CSF_GameCores.sql').read_text())
            self.assertEqual(db.execute('SELECT * FROM GameCores').fetchall(),[
                ('Base','base','a'),('Expansion1','xp1','b'),
                ('Expansion2','DE55664B-313E-451F-9488-23F168359B9D','GameCore_XP2_Shell')])

    def test_rejects_changed_shared_dependency_without_creating_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            shell=base/'shell/GameCore_XP2_Shell_FinalRelease.dll'
            shell.parent.mkdir()
            shell.write_bytes(b'changed dependency')
            with patch.object(package,'SHARED',base),self.assertRaisesRegex(ValueError,'dependency changed'):
                package.package(base/'out')
            self.assertFalse((base/'out').exists())

    def test_existing_candidate_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'CityStateFounder'
            out.mkdir()
            (out/'keep.txt').write_text('old evidence')
            with self.assertRaisesRegex(ValueError,'fresh'):
                package.package(out)
            self.assertEqual((out/'keep.txt').read_text(),'old evidence')

    def test_changed_provenance_is_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)/'out'
            with patch.object(package,'LOADER_REPORT_SHA','0'*64),self.assertRaisesRegex(ValueError,'provenance changed'):
                package.package(out)
            self.assertFalse(out.exists())

    def test_stale_gameplay_plugin_is_rejected(self):
        old = ROOT.parent/'torelease/Workshop_1.1.1_final2/CityStateFounder/Binaries/Win64/Plugins/GameCore/CityStateFounder.dll'
        with self.assertRaisesRegex(ValueError,'Rebuild the v1.1.2'):
            package.checked_plugin(old)

if __name__=='__main__':
    unittest.main()
