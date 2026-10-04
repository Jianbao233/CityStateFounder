import sqlite3, os, sys, io, glob
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI")
for f in glob.glob(os.path.join(base, "**", "*.sqlite"), recursive=True):
    try:
        c = sqlite3.connect(f)
        r = c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='CityStates'").fetchone()
        if r:
            print(f"  ★ CityStates 在: {os.path.relpath(f, base)}")
            cols = [x[1] for x in c.execute("PRAGMA table_info(CityStates)")]
            print(f"    列: {cols}")
            n = c.execute("SELECT COUNT(*) FROM CityStates").fetchone()[0]
            print(f"    行数: {n}")
            for row in c.execute("SELECT * FROM CityStates LIMIT 2"):
                print("    ", dict(zip(cols, row)))
            ours = c.execute("SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
            print(f"    我们的 6 个在其中: {ours} 行")
        c.close()
    except Exception:
        pass