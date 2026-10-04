import sqlite3, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
db = os.path.join(os.environ['LOCALAPPDATA'],
                  "Firaxis Games", "Sid Meier's Civilization VI", "Cache", "DebugGameplay.sqlite")
c = sqlite3.connect(db)

print("=== DuplicateCivilizations 表结构 ===")
ddl = c.execute("SELECT sql FROM sqlite_master WHERE name='DuplicateCivilizations'").fetchone()
print("  ", (ddl[0] if ddl else "(表不存在)").replace("\n", " ")[:220])

print()
print("=== 官方原有多少行 ===")
print("  ", c.execute("SELECT COUNT(*) FROM DuplicateCivilizations").fetchone()[0])

print()
print("=== PRESLAV 的登记 ===")
rows = list(c.execute(
    "SELECT * FROM DuplicateCivilizations "
    "WHERE CivilizationType='CIVILIZATION_PRESLAV' "
    "   OR OtherCivilizationType='CIVILIZATION_PRESLAV'"))
print(f"  行数 = {len(rows)}")
for r in rows[:5]:
    print("   ", r)

print()
print("=== 我们 6 个城邦的登记 ===")
n = c.execute("SELECT COUNT(*) FROM DuplicateCivilizations "
              "WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
print(f"  行数 = {n}")

print()
print("=== 有登记的城市邦（前 15）===")
for r in c.execute("SELECT DISTINCT CivilizationType FROM DuplicateCivilizations LIMIT 15"):
    print("   ", r[0])

print()
print("=== 全部 48 个官方城邦里，有多少有登记 ===")
cs = [r[0] for r in c.execute(
    "SELECT CivilizationType FROM Civilizations "
    "WHERE StartingCivilizationLevelType='CIVILIZATION_LEVEL_CITY_STATE'")]
have = 0
for x in cs:
    k = c.execute("SELECT COUNT(*) FROM DuplicateCivilizations WHERE CivilizationType=?", (x,)).fetchone()[0]
    if k > 0:
        have += 1
print(f"  官方城邦 {len(cs)} 个，其中有 DuplicateCivilizations 登记的 {have} 个")
print()
print("  没有登记的（前 20）:")
miss = [x for x in cs if c.execute(
    "SELECT COUNT(*) FROM DuplicateCivilizations WHERE CivilizationType=?", (x,)).fetchone()[0] == 0]
for x in miss[:20]:
    print("   ", x)
print(f"  → 共 {len(miss)} 个没有登记")
