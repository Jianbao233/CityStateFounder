# -*- coding: utf-8 -*-
"""生成「能力重复、名字不同」的自定义城邦：SQL + 本地化文案。

依据（全部来自实机数据库反查，见 docs/DLL版_调研设计与计划.md 附录 E）：
  Civilizations        (CivilizationType, Name, Description, Adjective,
                        RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
  Leaders              (LeaderType, Name, OperationList, IsBarbarianLeader,
                        InheritFrom, SceneLayers, Sex, SameSexPercentage)
  CivilizationLeaders  (LeaderType, CivilizationType, CapitalName)
  LeaderTraits         (LeaderType, TraitType)      ← ★ 能力在这里

「能力重复但名字不同」= 各城邦文明/领袖名不同，但 LeaderTraits 指向【同一个 Trait】。
"""
import io, os, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."

# ── 要造的城邦：名字 + 挂哪个 Trait（Trait 相同 = 能力相同）────────────────
# Trait 取自原版（LeaderTraits 里的 MINOR_CIV_*_TRAIT）
CITY_STATES = [
    # (编号, 中文名, 英文名, Trait（决定能力）, 民族)
    ("01", "新亚历山大", "Neo Alexandria", "MINOR_CIV_SCIENTIFIC_TRAIT",   "ETHNICITY_MEDITERRANEAN"),
    ("02", "新孟菲斯",   "Neo Memphis",    "MINOR_CIV_SCIENTIFIC_TRAIT",   "ETHNICITY_MEDITERRANEAN"),  # ← 与 01 同能力
    ("03", "新乌鲁克",   "Neo Uruk",       "MINOR_CIV_CULTURAL_TRAIT",     "ETHNICITY_MID_EAST"),
    ("04", "新尼尼微",   "Neo Nineveh",    "MINOR_CIV_CULTURAL_TRAIT",     "ETHNICITY_MID_EAST"),       # ← 与 03 同能力
    ("05", "新迦太基",   "Neo Carthage",   "MINOR_CIV_TRADE_TRAIT",        "ETHNICITY_MEDITERRANEAN"),
    ("06", "新推罗",     "Neo Tyre",       "MINOR_CIV_TRADE_TRAIT",        "ETHNICITY_MID_EAST"),       # ← 与 05 同能力
]

CIV_PREFIX = "CIVILIZATION_CSF_CS_"
LEADER_PREFIX = "LEADER_MINOR_CIV_CSF_CS_"
LOC_PREFIX = "LOC_CSF_CS_"

sql = []
sql.append("-- CSF_CustomCityStates.sql")
sql.append("-- 「能力重复、名字不同」的自定义城邦 —— 由 tools/_gen_custom_cs.py 生成，请勿手改。")
sql.append("--")
sql.append("-- 原理：城邦能力由 LeaderTraits 承载；各城邦名字/领袖不同，")
sql.append("--       但指向【同一个 Trait】→ 能力完全相同、名字各自独立。")
sql.append("-- 数据模型依据见 docs/DLL版_调研设计与计划.md 附录 E。")
sql.append("")
sql.append("-- 幂等：全部 INSERT OR IGNORE，重复加载安全")
sql.append("")
sql.append("-- ⚠️⚠️ 顺序很重要：Types 必须先登记，否则 Civilizations / Leaders 的外键失败。")
sql.append("--   实测踩到（在数据库副本上逐条跑）：")
sql.append("--       INSERT INTO Civilizations -> FOREIGN KEY constraint failed")
sql.append("--   原因：Civilizations.CivilizationType -> Types.Type（外键）")
sql.append("--   Types.Hash 由触发器 OnTypeInsert 调 Make_Hash 自动算，不用我们给。")
sql.append("")
for num, zh, en, trait, ethnic in CITY_STATES:
    sql.append(f"INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('{CIV_PREFIX}{num}', 'KIND_CIVILIZATION');")
    sql.append(f"INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('{LEADER_PREFIX}{num}', 'KIND_LEADER');")
sql.append("")

for num, zh, en, trait, ethnic in CITY_STATES:
    civ = CIV_PREFIX + num
    leader = LEADER_PREFIX + num
    sql.append(f"-- ── {zh} / {en}（能力：{trait}）")
    sql.append(
        "INSERT OR IGNORE INTO Civilizations\n"
        "  (CivilizationType, Name, Description, Adjective,\n"
        "   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)\n"
        f"VALUES ('{civ}', '{LOC_PREFIX}{num}_NAME', '{LOC_PREFIX}{num}_DESC',\n"
        f"        '{LOC_PREFIX}{num}_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', '{ethnic}');"
    )
    sql.append("")
    sql.append(
        "INSERT OR IGNORE INTO Leaders\n"
        "  (LeaderType, Name, OperationList, IsBarbarianLeader,\n"
        "   InheritFrom, SceneLayers, Sex, SameSexPercentage)\n"
        f"VALUES ('{leader}', '{LOC_PREFIX}{num}_LEADER_NAME', NULL, 0,\n"
        f"        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);"
    )
    sql.append("")
    sql.append(
        "INSERT OR IGNORE INTO CivilizationLeaders\n"
        "  (LeaderType, CivilizationType, CapitalName)\n"
        f"VALUES ('{leader}', '{civ}', '{LOC_PREFIX}{num}_CAPITAL');"
    )
    sql.append("")
    sql.append(
        "-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同\n"
        "INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)\n"
        f"VALUES ('{leader}', '{trait}');"
    )
    sql.append("")

sql.append("-- ── 允许它们与原版城邦共存（别名语义，见 DuplicateCivilizations）")
sql.append("--    ⚠️ 两张表成对登记；官方 DuplicateCivilizations 为空、DuplicateLeaders 有 10 行")
for num, zh, en, trait, ethnic in CITY_STATES:
    civ = CIV_PREFIX + num
    for other in ("CIVILIZATION_GENEVA", "CIVILIZATION_BRUSSELS"):
        sql.append(
            "INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)\n"
            f"VALUES ('{civ}', '{other}');"
        )
sql.append("")

sql_path = os.path.join(OUT_DIR, "CSF_CustomCityStates.sql")
with open(sql_path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(sql))
print(f"✅ SQL   -> {sql_path}  ({len(sql)} 行)")

# ── 本地化 ────────────────────────────────────────────────────────────────
rows = []
for num, zh, en, trait, ethnic in CITY_STATES:
    rows.append((f"{LOC_PREFIX}{num}_NAME",           en,             zh))
    rows.append((f"{LOC_PREFIX}{num}_DESC",           f"A city-state of {en}.", f"{zh}城邦。"))
    rows.append((f"{LOC_PREFIX}{num}_ADJ",            en,             zh))
    rows.append((f"{LOC_PREFIX}{num}_LEADER_NAME",    f"{en} Council", f"{zh}议会"))
    rows.append((f"{LOC_PREFIX}{num}_CAPITAL",        en,             zh))

xml = ['<?xml version="1.0" encoding="utf-8"?>',
       '<GameData>',
       '  <!-- 「能力重复、名字不同」的自定义城邦文案 —— 由 tools/_gen_custom_cs.py 生成 -->',
       '  <LocalizedText>']
for tag, en, zh in rows:
    xml.append(f'    <Replace Tag="{tag}" Language="en_US"><Text>{en}</Text></Replace>')
    xml.append(f'    <Replace Tag="{tag}" Language="zh_Hans_CN"><Text>{zh}</Text></Replace>')
xml.append('  </LocalizedText>')
xml.append('</GameData>')

xml_path = os.path.join(OUT_DIR, "CSF_CustomCityStates_Text.xml")
with open(xml_path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(xml) + "\n")
print(f"✅ 文案  -> {xml_path}  ({len(rows)} 个词条 × 2 语言)")

print()
print("城邦一览（★ 表示能力相同）:")
for num, zh, en, trait, ethnic in CITY_STATES:
    print(f"  {num}  {zh:8} {en:18} {trait}")
