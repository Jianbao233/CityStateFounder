import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
gp = sqlite3.connect(os.path.join(base, "DebugGameplay.sqlite"))
print("  === 开拓者 SETTLER ===")
for r in gp.execute("SELECT UnitType, Domain, FormationClass, FoundCity, FoundReligion, MakeTradeRoute, BuildCharges FROM Units WHERE UnitType LIKE '%SETTLER%'"):
    print("    ", r)
print()
print("  === 我们的使节 ===")
for r in gp.execute("SELECT UnitType, Domain, FormationClass, FoundCity, FoundReligion, MakeTradeRoute, BuildCharges FROM Units WHERE UnitType='UNIT_CSF_ENVOY'"):
    print("    ", r)
print()
print("  === Units_XP2 结构 ===")
cols2 = [x[1] for x in gp.execute("PRAGMA table_info(Units_XP2)")]
print("    ", cols2)
print()
print("  === UnitAbilities 里 SETTLER 有什么 ===")
try:
    for r in gp.execute("SELECT * FROM UnitAbilities WHERE UnitType LIKE '%SETTLER%'"):
        print("    ", r)
except Exception as e: print("    ", e)
print()
print("  === 有没有 FOUND_CITY 相关的 UnitAbility / Action ===")
for t in ('UnitAbilities','Types','UnitOperations'):
    try:
        cols = [x[1] for x in gp.execute(f"PRAGMA table_info({t})")]
        for r in gp.execute(f"SELECT * FROM {t} WHERE " + " OR ".join([f"{c} LIKE '%FOUND%'" for c in cols if 'type' in c.lower() or 'name' in c.lower() or 'id' in c.lower()]) + " LIMIT 8"):
            print(f"    {t}:", r)
    except Exception as e: pass