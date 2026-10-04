import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
cfg = sqlite3.connect(os.path.join(base, "DebugConfiguration.sqlite"))
gp  = sqlite3.connect(os.path.join(base, "DebugGameplay.sqlite"))

print("=== ① PlayerColors 表结构 ===")
ddl = cfg.execute("SELECT sql FROM sqlite_master WHERE name='PlayerColors'").fetchone()
print("  ", (ddl[0] if ddl else "?").replace("\n", " ")[:260])
print()
print("=== ② 我们的 6 个在 PlayerColors 里吗 ===")
n = cfg.execute("SELECT COUNT(*) FROM PlayerColors WHERE Type LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
print(f"  行数 = {n}")
for r in cfg.execute("SELECT Type, Usage, PrimaryColor, SecondaryColor FROM PlayerColors WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 3"):
    print("   ", r)
print()
print("=== ③ 我们的 6 个在 CityStates 里吗（配置库）===")
n2 = cfg.execute("SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
print(f"  行数 = {n2}   ← 应为 18（6 城邦 × 3 域）")
for r in cfg.execute("SELECT Domain, CivilizationType, CityStateCategory, Icon FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 4"):
    print("   ", r)
print()
print("=== ④ TypeProperties 里的 CityStateCategory（玩法库）===")
try:
    n3 = gp.execute("SELECT COUNT(*) FROM TypeProperties WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' AND Name='CityStateCategory'").fetchone()[0]
    print(f"  行数 = {n3}   ← 应为 6")
    for r in gp.execute("SELECT Type, Value FROM TypeProperties WHERE Type LIKE 'CIVILIZATION_CSF_CS_%' AND Name='CityStateCategory' LIMIT 6"):
        print("   ", r)
except Exception as e:
    print("  查询失败:", e)
print()
print("=== ⑤ LeaderTraits（能力共享）===")
try:
    for r in gp.execute("SELECT LeaderType, TraitType FROM LeaderTraits WHERE LeaderType LIKE 'LEADER_MINOR_CIV_CSF_CS_%'"):
        print("   ", r)
except Exception as e:
    print("  查询失败:", e)