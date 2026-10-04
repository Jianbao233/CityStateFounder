import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
f = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache", "DebugConfiguration.sqlite")
c = sqlite3.connect(f)
print("=== DomainValues 表结构 ===")
ddl = c.execute("SELECT sql FROM sqlite_master WHERE name='DomainValues'").fetchone()
print("  ", (ddl[0] if ddl else "?").replace("\n", " ")[:300])
print()
print("=== DomainValues 里的 CityState 相关域 ===")
cols = [x[1] for x in c.execute("PRAGMA table_info(DomainValues)")]
print("  列:", cols)
try:
    for r in c.execute("SELECT * FROM DomainValues WHERE Domain LIKE '%CityState%' LIMIT 10"):
        print("   ", r)
except Exception as e:
    print("  失败:", e)
print()
print("=== 全部 Domain 名（含 CityState 的）===")
try:
    for r in c.execute("SELECT DISTINCT Domain FROM DomainValues"):
        if 'CityState' in str(r[0]): print("   ", r[0])
except Exception as e:
    print("  失败:", e)
print()
print("=== 官方 24 行 CityStates 的 CivilizationType 样例 ===")
for r in c.execute("SELECT Domain, CivilizationType, CityStateCategory FROM CityStates LIMIT 5"):
    print("   ", r)