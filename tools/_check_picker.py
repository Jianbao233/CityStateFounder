import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
cfg = sqlite3.connect(os.path.join(base, "DebugConfiguration.sqlite"))

print("=== ① Parameters 表里有没有我们的 6 个 ===")
try:
    cols = [x[1] for x in cfg.execute("PRAGMA table_info(Parameters)")]
    print("  列:", cols)
    n = cfg.execute("SELECT COUNT(*) FROM Parameters WHERE ParameterId LIKE 'LEADER_MINOR_CIV_CSF_CS_%'").fetchone()[0]
    print(f"  我们的行数 = {n}   ← 应为 6")
    for r in cfg.execute("SELECT ParameterId, Name, ConfigurationId, GroupId FROM Parameters WHERE ParameterId LIKE 'LEADER_MINOR_CIV_CSF_CS_%' LIMIT 3"):
        print("   ", r)
except Exception as e:
    print("  失败:", e)

print()
print("=== ② ParameterDependencies ===")
try:
    n2 = cfg.execute("SELECT COUNT(*) FROM ParameterDependencies WHERE ParameterId LIKE 'LEADER_MINOR_CIV_CSF_CS_%'").fetchone()[0]
    print(f"  我们的行数 = {n2}   ← 应为 6")
    for r in cfg.execute("SELECT ParameterId, ConfigurationId, ConfigurationValue FROM ParameterDependencies WHERE ParameterId LIKE 'LEADER_MINOR_CIV_CSF_CS_%' LIMIT 3"):
        print("   ", r)
except Exception as e:
    print("  失败:", e)

print()
print("=== ③ CityStates（配置库）===")
try:
    n3 = cfg.execute("SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
    print(f"  我们的行数 = {n3}   ← 应为 18")
    for r in cfg.execute("SELECT Domain, CivilizationType, CityStateCategory FROM CityStates WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%' LIMIT 4"):
        print("   ", r)
except Exception as e:
    print("  失败:", e)

print()
print("=== ④ 对比：官方城邦在 Parameters 里的写法（举例）===")
try:
    for r in cfg.execute("SELECT ParameterId, Name, ConfigurationId, GroupId, SortIndex FROM Parameters WHERE ConfigurationId LIKE 'LEADER_MINOR_CIV_%' LIMIT 3"):
        print("   ", r)
except Exception as e:
    print("  失败:", e)