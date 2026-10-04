import sqlite3, os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
db = os.path.join(os.environ['LOCALAPPDATA'], "Firaxis Games", "Sid Meier's Civilization VI",
                  "Cache", "DebugGameplay.sqlite")
c = sqlite3.connect(db)
cs = [r[0] for r in c.execute(
    "SELECT CivilizationType FROM Civilizations "
    "WHERE StartingCivilizationLevelType='CIVILIZATION_LEVEL_CITY_STATE' "
    "  AND CivilizationType NOT LIKE 'CIVILIZATION_CSF_CS_%' "
    "ORDER BY CivilizationType")]
print("-- 自动生成：官方城邦的"自我共存"登记（DuplicateCivilizations）")
print("--")
print("-- 语义：DuplicateCivilizations 表示"这两个文明可以共存"。")
print("-- 用途：让【同一个城邦能被复制多份】—— 不加登记就复制会让引擎崩溃。")
print("-- 实测（2026-10-04）：官方 54 个城邦原本【全都没有登记】，")
print("--   造副本后点下一回合 → 游戏原生崩溃（无 Lua 报错）。")
print("--")
print("-- ⚠️ 只列官方城邦。自制城邦（CIVILIZATION_CSF_CS_*）已下架，")
print("--    若在此引用它们会报 Invalid Reference → 数据库错误 → 进不了对局。")
print("")
for x in cs:
    print(f"INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('{x}', '{x}');")
print("")
print(f"-- 共 {len(cs)} 个官方城邦")