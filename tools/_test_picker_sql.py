import sqlite3, os, sys, io, shutil, tempfile
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
src = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI",
                   "Cache", "DebugConfiguration.sqlite")
tmp = os.path.join(tempfile.gettempdir(), "cfg_test.sqlite")
shutil.copy2(src, tmp)
c = sqlite3.connect(tmp)
c.execute("PRAGMA foreign_keys=ON")

sqlfile = sys.argv[1]
txt = open(sqlfile, encoding='utf-8').read()
stmts = [s.strip() for s in txt.split(';') if s.strip() and not s.strip().startswith('--')]
print(f"  共 {len(stmts)} 条语句")
ok, bad = 0, 0
for s in stmts:
    try:
        c.execute(s)
        ok += 1
    except Exception as e:
        bad += 1
        if bad <= 5:
            print(f"  ❌ {e}")
            print(f"     {s[:150]}")
c.commit()
print(f"  成功 {ok} / 失败 {bad}")
print(f"  插入后 CityStates 含 CSF: {c.execute(chr(34)+'SELECT COUNT(*) FROM CityStates WHERE CivilizationType LIKE ' + chr(39) + '%CSF%' + chr(39) + chr(34)).fetchone()[0]}")