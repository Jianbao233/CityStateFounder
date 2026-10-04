import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
gp = sqlite3.connect(os.path.join(base, "DebugGameplay.sqlite"))
print("=== PlayerColors 表结构 ===")
ddl = gp.execute("SELECT sql FROM sqlite_master WHERE name='PlayerColors'").fetchone()
print("  ", (ddl[0] if ddl else "?").replace("\n", " ")[:220])
print()
print("=== VATICAN_CITY 有没有 PlayerColors 行 ===")
for r in gp.execute("SELECT * FROM PlayerColors WHERE Type LIKE '%VATICAN%'"):
    print("  ", r)
n = gp.execute("SELECT COUNT(*) FROM PlayerColors WHERE Type LIKE '%VATICAN%'").fetchone()[0]
print(f"  行数 = {n}")
print()
print("=== 我们的 6 个城邦 ===")
for r in gp.execute("SELECT Type, Usage, PrimaryColor, SecondaryColor FROM PlayerColors WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 3"):
    print("  ", r)
print()
print("=== PlayerColors 总行数 + Usage 分布 ===")
print("  总数:", gp.execute("SELECT COUNT(*) FROM PlayerColors").fetchone()[0])
for r in gp.execute("SELECT Usage, COUNT(*) FROM PlayerColors GROUP BY Usage"):
    print("   ", r)
print()
print("=== Colors 表里有没有 COLOR_PLAYER_CITY_STATE_* ===")
try:
    for r in gp.execute("SELECT ColorType, Red, Green, Blue, Alpha FROM Colors WHERE ColorType LIKE 'COLOR_PLAYER_CITY_STATE%' LIMIT 8"):
        print("  ", r)
except Exception as e:
    print("  Colors 表查询失败:", e)