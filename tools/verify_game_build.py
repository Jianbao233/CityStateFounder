"""Read-only full XP2 comparison for the reviewed Steam build26407122.

Only build-directory identifiers, debug timestamps/CodeView GUID and export
timestamp may differ inside sections. No instructions, vtables, imports,
gameplay data or relocations are masked. Does not execute either image.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import pefile

ROOT = Path(__file__).resolve().parents[1]
GAME = Path("F:/Steam/steamapps/common/Sid Meier's Civilization VI")
OLD = (ROOT / '../../../C6FW/_official_backup/Expansion2/GameCore_XP2_FinalRelease.dll').resolve()
CORE = GAME / 'DLC/Expansion2/Binaries/Win64/GameCore_XP2_FinalRelease.dll'
OLD_SHA = '324c51e9ea3531758842e16c69e6cddbefbb226c5b675c3d6e60111646c2e98c'
NEW_SHA = '092abfbb2176f8df04b5212f819dc269dd83aea866ff05aaf489904a1ff7c41f'
EXES = {'CivilizationVI.exe': 'd1a0cfd439e7451be515f47595cfa0b6b983f56d1faf4ea434a4ce3b21491ebe',
        'CivilizationVI_DX12.exe': '1adb1a2bca31f9db6be14d6e22d30d2dfcb6dcd8de3abd9a81e7bea396b39417'}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def normalized_rdata(pe, section):
    data = bytearray(section.get_data())
    # Proven compiler source-path identifier, not arbitrary hexadecimal text.
    count = 0
    for sep in (b'\\', b'/'):
        old = sep + b'work' + sep + b'26d31e7d2eca7bbe' + sep
        new = sep + b'work' + sep + b'e9c5035e29e72a4c' + sep
        count += data.count(old) + data.count(new)
        data = data.replace(old, new)
    assert count == 533
    def zero(rva, size):
        offset = rva - section.VirtualAddress
        assert 0 <= offset and offset + size <= len(data)
        data[offset:offset+size] = bytes(size)
    debug_dir = pe.OPTIONAL_HEADER.DATA_DIRECTORY[6]
    assert len(pe.DIRECTORY_ENTRY_DEBUG) == 3
    for index, entry in enumerate(pe.DIRECTORY_ENTRY_DEBUG):
        zero(debug_dir.VirtualAddress + index * 28 + 4, 4)  # timestamp
        if entry.struct.Type == 2:
            rva = entry.struct.AddressOfRawData
            assert pe.get_data(rva, 4) == b'RSDS'
            zero(rva + 4, 16)  # PDB GUID only; path/age remain compared
    zero(pe.OPTIONAL_HEADER.DATA_DIRECTORY[0].VirtualAddress + 4, 4)
    return bytes(data)

def verify(old=OLD, core=CORE, game=GAME):
    assert sha(old) == OLD_SHA, 'Unreviewed reference core'
    assert sha(core) == NEW_SHA, 'Unreviewed target core'
    a, b = pefile.PE(str(old)), pefile.PE(str(core))
    assert a.FILE_HEADER.Machine == b.FILE_HEADER.Machine == 0x8664
    assert a.OPTIONAL_HEADER.ImageBase == b.OPTIONAL_HEADER.ImageBase
    assert a.OPTIONAL_HEADER.SizeOfImage == b.OPTIONAL_HEADER.SizeOfImage
    assert len(a.sections) == len(b.sections) == 8
    sections = []
    for x, y in zip(a.sections, b.sections):
        assert (x.Name,x.VirtualAddress,x.Misc_VirtualSize,x.SizeOfRawData,x.Characteristics) == (
                y.Name,y.VirtualAddress,y.Misc_VirtualSize,y.SizeOfRawData,y.Characteristics)
        raw_equal = x.get_data() == y.get_data()
        if x.Name.rstrip(b'\0') == b'.rdata':
            assert normalized_rdata(a,x) == normalized_rdata(b,y), 'Non-metadata .rdata changed'
        else:
            assert raw_equal, x.Name
        sections.append({'name':x.Name.rstrip(b'\0').decode(), 'rva':hex(x.VirtualAddress),
                         'bytes':x.SizeOfRawData, 'byte_identical':raw_equal})
    exports = lambda p: sorted((e.name.decode() if e.name else '',e.ordinal,e.address) for e in p.DIRECTORY_ENTRY_EXPORT.symbols)
    assert exports(a) == exports(b) and len(exports(a)) == 157
    imports = lambda p: [(d.dll.decode(), d.struct.FirstThunk,
                         [(i.name.decode() if i.name else '',i.ordinal) for i in d.imports]) for d in p.DIRECTORY_ENTRY_IMPORT]
    assert imports(a) == imports(b)
    exe_root = game/'Base/Binaries/Win64Steam'
    for name, expected in EXES.items():
        assert sha(exe_root/name) == expected, 'Unreviewed EXE: '+name
    bridge = (ROOT/'native/csf_bridge.cpp').read_text(encoding='utf-8')
    required = set(re.findall(r'"(\?[^"\n]+@@[^"\n]+)"', bridge))
    hks = pefile.PE(str(exe_root/'HavokScript_FinalRelease.dll'))
    available = {e.name.decode() for e in hks.DIRECTORY_ENTRY_EXPORT.symbols if e.name}
    assert len(required) >= 10 and required <= available, required-available
    return {'status':'STATIC_PASS', 'game_build':26407122, 'old_core_sha256':OLD_SHA,
            'core_sha256':NEW_SHA, 'exe_sha256':EXES, 'sections':sections,
            'rdata_allowed_changes':['533 compiler work-directory IDs','3 debug timestamps','CodeView GUID','export timestamp'],
            'exports_equal':157, 'imports_equal':True, 'bridge_hks_exports':len(required),
            'hks_sha256':sha(exe_root/'HavokScript_FinalRelease.dll'),
            'runtime_game':'NOT_RUN', 'multiplayer':'NOT_RUN'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), 'Preserve earlier evidence'
    result = verify()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
