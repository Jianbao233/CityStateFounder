"""Build isolated CSF shared-Loader candidate; does not deploy or call Steam."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import sqlite3
import xml.etree.ElementTree as ET
import pefile
import verify_game_build

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src'
VERSION = '1.1.2'
MOD_VERSION = 112
SHARED = (ROOT / '../../PVPCore/build/shared_loader_winmm_candidate/public-build26407122-1.0.6-20261106').resolve()
LOADER_REPORT_SHA = '83c01e88f5c176280d245750f80a95e9c8f22b47c3c1c95334bb5de4ea52fc1f'
PINNED = {
    'shell/GameCore_XP2_Shell_FinalRelease.dll': 'e207bc3070f14b8bc26fb04df4a2eda9803e6525b8ce5bff2373a65eb6384acc',
    'runtime/Civ6DllLoader.winmm.runtime.dll': '1d26e90118d8f7faec0a7f5dfbf1d2696809a8095093b2ccaca2d07ba75b44e7',
}
PLUGIN = 'Binaries/Win64/Plugins/GameCore/CityStateFounder.dll'
HOOK_API_SHA = 'e03028ba3e489a0ee2517a6c78499d73d4b2743b6c2b2e89dfa27a3485dfa9f3'
def sha(data):
    return hashlib.sha256(data).hexdigest()

def checked_plugin(path):
    data = path.read_bytes()
    pe = pefile.PE(data=data)
    version = pe.VS_FIXEDFILEINFO[0]
    if (version.FileVersionMS,version.FileVersionLS) != (0x10001,0x20000):
        raise ValueError('Rebuild the v1.1.2 gameplay plugin before packaging')
    names = {e.name for e in pe.DIRECTORY_ENTRY_EXPORT.symbols}
    if names != {b'OnLoad',b'OnUnload',b'Civ6PluginKind'}:
        raise ValueError('Unexpected native plugin ABI')
    return data

def package(out, loader_dir=None, game_dir=verify_game_build.GAME, reference_xp2=verify_game_build.OLD):
    if out.exists():
        raise ValueError('Candidate output must be fresh; preserve earlier artifacts')
    xml = (SRC / 'CityStateFounder.modinfo').read_bytes()
    tree = ET.fromstring(xml)
    if tree.get('version') != str(MOD_VERSION):
        raise ValueError('Source manifest version does not match the packager')
    dependencies = {'Binaries/Win64/' + Path(name).name for name in PINNED}
    declared = [node.text.strip() for node in tree.findall('./Files/File')]
    for name in declared:
        path = PurePosixPath(name)
        if not path.parts or path.is_absolute() or '..' in path.parts or ':' in name or '\\' in name:
            raise ValueError('Unsafe file declaration: ' + name)
    if set(name for name in declared if name.endswith('.dll')) != dependencies | {PLUGIN}:
        raise ValueError('Unexpected DLL declarations in source manifest')
    if len({name.casefold() for name in declared}) != len(declared):
        raise ValueError('Duplicate file declarations in source manifest')
    payload = {name:(SRC / name).read_bytes() for name in declared
               if name not in dependencies and name != PLUGIN}
    for name, expected in PINNED.items():
        filename = Path(name).name
        source = SHARED / name if loader_dir is None else loader_dir / filename
        data = source.read_bytes()
        if sha(data) != expected:
            raise ValueError('Shared dependency changed: ' + name)
        payload['Binaries/Win64/' + filename] = data
    if loader_dir is None:
        report_bytes = (SHARED/'latest-result.json').read_bytes()
        if sha(report_bytes) != LOADER_REPORT_SHA:
            raise ValueError('Shared dependency provenance changed')
    if sha((ROOT/'native/vendor/HookAPI.h').read_bytes()) != HOOK_API_SHA:
        raise ValueError('Plugin/Loader HookAPI mismatch')
    compatibility = verify_game_build.verify(
        old=reference_xp2,
        core=game_dir/'DLC/Expansion2/Binaries/Win64/GameCore_XP2_FinalRelease.dll',
        game=game_dir,
    )
    plugin = ROOT / 'build/shared_native/CityStateFounder.dll'
    payload[PLUGIN] = checked_plugin(plugin)
    payload['CityStateFounder.modinfo'] = xml
    db = sqlite3.connect(':memory:')
    db.executescript('CREATE TABLE GameCores(GameCore TEXT PRIMARY KEY,PackageId TEXT,DllPrefix TEXT);'
                     "INSERT INTO GameCores VALUES('Base','base','GameCore_Base'),('Expansion1','xp1','GameCore_XP1'),('Expansion2','xp2','GameCore_XP2');")
    db.executescript(payload['Config/CSF_GameCores.sql'].decode())
    assert db.execute('SELECT * FROM GameCores').fetchall() == [
        ('Base','base','GameCore_Base'), ('Expansion1','xp1','GameCore_XP1'),
        ('Expansion2','DE55664B-313E-451F-9488-23F168359B9D','GameCore_XP2_Shell')]
    assert set(declared) == set(payload)-{'CityStateFounder.modinfo'}
    payload['LICENSE.txt'] = (ROOT / 'LICENSE').read_bytes()
    payload['THIRD_PARTY_NOTICES.txt'] = (ROOT / 'docs/SHARED_LOADER_NOTICES.txt').read_bytes()
    payload['README_TEST.zh-CN.md'] = '''城邦缔造者 v1.1.2（本地适配候选）
适配 Steam Windows build26407122，使用与 CCB 工具箱2.0.38-beta相同的CCB兼容版加载器1.0.6。
该加载器是基于Civ6DllLoader的过渡兼容分支，与上游原版存在差异。
Windows 64位、风云变幻规则；不开蛮族氏族也可使用，不改变开局城邦数量。
启用MOD后首次加载风云变幻时，公共加载器安装WINMM运行时并提示重启。
确认后等待游戏重新启动，再开局或读档。不要并用旧式GameCore替换或旧版公共加载壳。
如果已有其它代理入口，加载器会拒绝接管；不要直接覆盖来历不明的文件。
MOD目录保留完整文件夹；不需要手工替换官方游戏DLL或XML。
联机未测试；不同存档、能力及模组组合未保证全部兼容，请备份存档。
诊断日志：MOD的Logs/CSFNative.log，以及游戏目录的公共Loader日志。
'''.encode('utf-8')
    manifest = {'schema':'csf-shared-loader-package-v1','version':VERSION,'mod_version':MOD_VERSION,
                'runtime':'WINMM/format2/1.0.6','runtime_status':'CANDIDATE_UNTIL_RUNTIME_ACCEPTANCE',
                'game_build':26407122, 'compatibility':compatibility,
                'loader_report_sha256':LOADER_REPORT_SHA,
                'official_xp2_sha256':compatibility['core_sha256'],
                'multiplayer':'NOT_TESTED_USER_EXCLUDED_20261028',
                'files':[{ 'path':n,'bytes':len(b),'sha256':sha(b)} for n,b in sorted(payload.items())]}
    payload['BUILD_MANIFEST.json'] = (json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    out.mkdir(parents=True)
    for name,data in payload.items():
        target = out/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(data)
    for entry in manifest['files']:
        assert sha((out/entry['path']).read_bytes()) == entry['sha256']
    print(json.dumps({'out':str(out),'files':len(payload),'bytes':sum(map(len,payload.values())),
                      'plugin_sha256':sha(plugin.read_bytes()),'state':'LOCAL_CANDIDATE'},indent=2))

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--loader-dir',type=Path,help='Binaries/Win64 from the pinned CCB Toolkit distribution')
    parser.add_argument('--game-dir',type=Path,default=verify_game_build.GAME)
    parser.add_argument('--reference-xp2',type=Path,default=verify_game_build.OLD,
                        help='Archived, previously accepted official XP2 DLL for section comparison')
    args = parser.parse_args()
    package(args.out.resolve(), args.loader_dir, args.game_dir, args.reference_xp2)
