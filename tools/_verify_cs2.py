import sqlite3, os, sys, io, glob
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
for f in sorted(glob.glob(os.path.join(base, "*.sqlite"))):
    name = os.path.basename(f)
    try:
        c = sqlite3.connect(f)
        t = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")]
        has = []
        for want in ("CityStates", "PlayerColors", "TypeProperties", "LeaderTraits"):
            if want in t: has.append(want)
        if has:
            print(f"  {name}: {has}")
            if "CityStates" in has:
                n = c.execute("SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
                print(f"    → 我们的城邦在 CityStates: {n} 行（应为 18）")
                for r in c.execute("SELECT Domain, CivilizationType, CityStateCategory FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 3"):
                    print("      ", r)
            if "PlayerColors" in has:
                try:
                    n2 = c.execute("SELECT COUNT(*) FROM PlayerColors WHERE Type LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
                    print(f"    → 我们的城邦在 PlayerColors: {n2} 行（应为 6）")
                    for r in c.execute("SELECT Type, Usage, PrimaryColor, SecondaryColor FROM PlayerColors WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 2"):
                        print("      ", r)
                except Exception as e:
                    print("      PlayerColors 查询失败:", e)
            if "TypeProperties" in has:
                n3 = c.execute("SELECT COUNT(*) FROM TypeProperties WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' AND Name='CityStateCategory'").fetchone()[0]
                print(f"    → 我们的城邦 TypeProperties: {n3} 行（应为 6）")
                for r in c.execute("SELECT Type, Value FROM TypeProperties WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 3"):
                    print("      ", r)
        c.close()
    except Exception:
        pass