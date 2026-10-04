import sqlite3, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
c = sqlite3.connect(sys.argv[1])
print("=== CityStates 表结构 ===")
ddl = c.execute("SELECT sql FROM sqlite_master WHERE name='CityStates'").fetchone()
print("  ", (ddl[0] if ddl else "(不存在)").replace("\n", " ")[:400])
print()
print("=== 官方城邦在 CityStates 里的样例（3 个）===")
cols = [x[1] for x in c.execute("PRAGMA table_info(CityStates)")]
print("  列:", cols)
for r in c.execute("SELECT * FROM CityStates LIMIT 3"):
    print("  ", dict(zip(cols, r)))
print()
print("=== 我们那 6 个在 CityStates 里有吗 ===")
n = c.execute("SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
print(f"  行数 = {n}   ← 0 就说明缺这张表的数据（面板 unknownType 的原因）")
print()
print("=== 官方城邦总数 vs CityStates 表行数 ===")
cs = c.execute("SELECT COUNT(*) FROM Civilizations WHERE StartingCivilizationLevelType='CIVILIZATION_LEVEL_CITY_STATE'").fetchone()[0]
t = c.execute("SELECT COUNT(*) FROM CityStates").fetchone()[0]
print(f"  城邦文明 {cs} 个，CityStates 表 {t} 行")