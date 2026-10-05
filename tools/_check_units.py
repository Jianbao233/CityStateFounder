import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache")
gp = sqlite3.connect(os.path.join(base, "DebugGameplay.sqlite"))
cols = [x[1] for x in gp.execute("PRAGMA table_info(Units)")]
print("  Units 表字段（与建城/动作相关）:")
for c in cols:
    if any(k in c.lower() for k in ('found','city','settle','action','operation','build','domain','formation','make')):
        print("    ", c)
print()
print("  === 开拓者（SETTLER）的关键字段 ===")
for r in gp.execute("SELECT UnitType, Domain, FormationClass, FoundCity, FoundReligion, MakeTradeRoute, CanCapture, MajorCivOnly FROM Units WHERE UnitType LIKE '%SETTLER%'"):
    print("    ", r)
print()
print("  === 我们的使节 UNIT_CSF_ENVOY ===")
for r in gp.execute("SELECT UnitType, Domain, FormationClass, FoundCity, MajorCivOnly FROM Units WHERE UnitType='UNIT_CSF_ENVOY'"):
    print("    ", r)
print()
print("  === Units_XP2 里有没有相关字段 ===")
try:
    cols2 = [x[1] for x in gp.execute("PRAGMA table_info(Units_XP2)")]
    print("    Units_XP2 字段:", cols2)
    for r in gp.execute("SELECT * FROM Units_XP2 WHERE UnitType IN ('UNIT_SETTLER','UNIT_CSF_ENVOY')"):
        print("    ", dict(zip(cols2, r)))
except Exception as e:
    print("    查询失败:", e)