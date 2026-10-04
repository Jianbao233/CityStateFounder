import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
f = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI", "Cache", "DebugConfiguration.sqlite")
c = sqlite3.connect(f)
print("=== CityStates 建表语句 ===")
ddl = c.execute("SELECT sql FROM sqlite_master WHERE name='CityStates'").fetchone()
print("  ", (ddl[0] if ddl else "?").replace("\n", " ")[:500])
print()
print("=== CityStates 当前内容 ===")
print("  总行数:", c.execute("SELECT COUNT(*) FROM CityStates").fetchone()[0])
for r in c.execute("SELECT Domain, COUNT(*) FROM CityStates GROUP BY Domain"):
    print("   Domain =", r)
print("  含 CSF:", c.execute("SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE '%CSF%'").fetchone()[0])
print()
print("=== 配置库里有没有 Civilizations 表 ===")
t = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Civilizations','Types','Domains','DomainValues')")]
print("  ", t)
if 'Civilizations' in t:
    print("  Civilizations 行数:", c.execute("SELECT COUNT(*) FROM Civilizations").fetchone()[0])
    print("  含 CSF:", c.execute("SELECT COUNT(*) FROM Civilizations WHERE CivilizationType LIKE '%CSF%'").fetchone()[0])
    for r in c.execute("SELECT CivilizationType FROM Civilizations WHERE CivilizationType LIKE '%CSF%' LIMIT 3"):
        print("   ", r)
if 'Types' in t:
    print("  Types 行数:", c.execute("SELECT COUNT(*) FROM Types").fetchone()[0])
    print("  含 CSF:", c.execute("SELECT COUNT(*) FROM Types WHERE Type LIKE '%CSF%'").fetchone()[0])