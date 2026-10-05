import sqlite3, os, sys, io, glob
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
for f in sorted(glob.glob(os.path.join(base, "*.sqlite"))):
    name = os.path.basename(f)
    try:
        c = sqlite3.connect(f)
        tabs = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")]
        hits = [t for t in tabs if 'action' in t.lower()]
        if hits:
            print(f"  {name}: {hits}")
            for t in hits:
                try:
                    n = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                    print(f"    {t}: {n} 行")
                    cols = [x[1] for x in c.execute(f"PRAGMA table_info({t})")]
                    print(f"      列: {cols}")
                    for r in c.execute(f"SELECT * FROM {t} LIMIT 5"):
                        print("      ", r)
                except Exception as e:
                    print("      失败:", e)
        c.close()
    except Exception:
        pass