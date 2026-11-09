"""Real PE comparison and negative controls; no DLL/game execution."""
import copy
import unittest
import pefile
import verify_game_build as v

class GameBuildTests(unittest.TestCase):
    def test_complete_installed_core_and_exes(self):
        result = v.verify()
        self.assertEqual(result['exports_equal'],157)
        self.assertTrue(result['imports_equal'])

    def test_normalization_preserves_gameplay_read_only_data_changes(self):
        old,new = pefile.PE(str(v.OLD)),pefile.PE(str(v.CORE))
        a,b = old.sections[1],new.sections[1]
        expected = v.normalized_rdata(old,a)
        self.assertEqual(expected,v.normalized_rdata(new,b))
        # Change an IAT byte, outside the allowed compiler/debug metadata.
        data = bytearray(b.get_data())
        data[0] ^= 1
        damaged = copy.copy(b)
        damaged.get_data = lambda: bytes(data)
        self.assertNotEqual(expected,v.normalized_rdata(new,damaged))

    def test_missing_build_path_is_not_silently_normalized(self):
        pe = pefile.PE(str(v.CORE))
        b = copy.copy(pe.sections[1])
        data = b.get_data().replace(b'e9c5035e29e72a4c',b'unknown_build_id',1)
        b.get_data = lambda: data
        with self.assertRaises(AssertionError):
            v.normalized_rdata(pe,b)

if __name__ == '__main__':
    unittest.main()
