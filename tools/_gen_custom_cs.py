# -*- coding: utf-8 -*-
"""城邦生成器 —— 按【官方级写法】产出 6 个自定义城邦的全部文件。

参考实现（工坊 3591345334「Modder群友城邦小合集」的安庆城邦）：
    Config.xml        配置库：城邦选择器参数
    Picker.sql        配置库：CityStates 表（通用 + XP1 + XP2 三个域）
    Colors.sql        配置库：PlayerColors（★ 颜色）
    Icon.xml          图标图集
    Text.xml          文案
    <Civ>.xml         玩法库：Types/TypeProperties/Civilizations/Leaders/LeaderTraits/...
    Icon/*.dds        12 个尺寸的图标美术

我们与它的差别：
    ★ 图标【复用官方】的（不自己做 dds）→ 只引用官方 ICON_*，不需要新图集
    ★ 能力【共享官方 Trait】→ 2 个城邦一组，满足"能力重复但名字不同"
    ★ 用 SQL 而不是 XML（与既有实现保持一致）

产出：
    Data/CSF_CustomCityStates.sql      玩法库：文明/领袖/等级/类别/领袖能力
    Data/CSF_CityStatePicker.sql       配置库：CityStates 表（3 域）
    Data/CSF_CityStateColors.sql       配置库：PlayerColors
    Data/CSF_CityStateConfig.xml       配置库：选择器参数
    Text/CSF_CustomCityStates_Text.xml 文案
"""
import os
import sys

# ── 城邦定义 ────────────────────────────────────────────────────────────────
# (编号, 中文名, 英文名, 官方 Trait（能力）, 城邦类别, 颜色后缀, 复用的官方图标)
#   ★ 能力共享：2 个城邦一组用同一个官方 Trait → "能力重复但名字不同"
#   ★ 类别必须与 Trait 匹配（面板靠 CityStateCategory 显示"类型"）
#   ★ SecondaryColor 用官方的 COLOR_PLAYER_CITY_STATE_<类别>_SECONDARY
CITY_STATES = [
    ("01", "新亚历山大", "Neo Alexandria", "MINOR_CIV_SCIENTIFIC_TRAIT", "SCIENTIFIC", "SCIENTIFIC", "ICON_CIVILIZATION_GENEVA"),
    ("02", "新孟菲斯",   "Neo Memphis",    "MINOR_CIV_SCIENTIFIC_TRAIT", "SCIENTIFIC", "SCIENTIFIC", "ICON_CIVILIZATION_HATTUSA"),
    ("03", "新乌鲁克",   "Neo Uruk",       "MINOR_CIV_CULTURAL_TRAIT",   "CULTURAL",   "CULTURAL",   "ICON_CIVILIZATION_KUMASI"),
    ("04", "新尼尼微",   "Neo Nineveh",    "MINOR_CIV_CULTURAL_TRAIT",   "CULTURAL",   "CULTURAL",   "ICON_CIVILIZATION_NAN_MADOL"),
    ("05", "新迦太基",   "Neo Carthage",   "MINOR_CIV_TRADE_TRAIT",      "TRADE",      "TRADE",      "ICON_CIVILIZATION_ZANZIBAR"),
    ("06", "新推罗",     "Neo Tyre",       "MINOR_CIV_TRADE_TRAIT",      "TRADE",      "TRADE",      "ICON_CIVILIZATION_VILNIUS"),
]

INHERIT = {"SCIENTIFIC": "LEADER_MINOR_CIV_SCIENTIFIC",
           "CULTURAL":   "LEADER_MINOR_CIV_CULTURAL",
           "TRADE":      "LEADER_MINOR_CIV_TRADE"}


def civ(i):    return "CIVILIZATION_CSF_CS_%s" % i
def leader(i): return "LEADER_MINOR_CIV_CSF_CS_%s" % i


def gen_gameplay_sql():
    L = []
    L.append("-- ===========================================================================")
    L.append("-- 城邦缔造者 —— 6 个自定义城邦（玩法库）")
    L.append("-- ★ 按【官方级写法】生成，参考工坊 3591345334「Modder群友城邦小合集」")
    L.append("-- 由 tools/_gen_custom_cs.py 生成，勿手改")
    L.append("-- ===========================================================================")
    L.append("")
    L.append("-- ① Types：文明 / 领袖必须先登记（否则外键失败，整份文件中止）")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('%s', 'KIND_CIVILIZATION');" % civ(n))
        L.append("INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('%s', 'KIND_LEADER');" % leader(n))
    L.append("")
    L.append("-- ② ★★★ TypeProperties：城邦类别 —— 【面板「类型」读的就是这个】")
    L.append("--    没有它 → 面板显示 unknownType（这是我们之前最大的缺陷）")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('%s', 'CityStateCategory', '%s');" % (civ(n), cat))
    L.append("")
    L.append("-- ③ Civilizations：等级 = 城邦（Adjective / RandomCityNameDepth 照官方写法）")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, "
                 "StartingCivilizationLevelType, RandomCityNameDepth) VALUES "
                 "('%s', 'LOC_CSF_CS_%s_NAME', 'LOC_CSF_CS_%s_DESC', 'LOC_CSF_CS_%s_ADJ', "
                 "'CIVILIZATION_LEVEL_CITY_STATE', 1);" % (civ(n), n, n, n))
    L.append("")
    L.append("-- ④ CivilizationLeaders：带 CapitalName（官方写法）")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) "
                 "VALUES ('%s', '%s', 'LOC_CSF_CS_%s_CITY');" % (civ(n), leader(n), n))
    L.append("")
    L.append("-- ⑤ CityNames：城市名（官方写法，缺了会没名字）")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('%s', 'LOC_CSF_CS_%s_CITY');" % (civ(n), n))
    L.append("")
    L.append("-- ⑥ Leaders：InheritFrom 用【官方对应类别的次要文明领袖】")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES "
                 "('%s', 'LOC_CSF_CS_%s_LEADER', '%s');" % (leader(n), n, INHERIT[cat]))
    L.append("")
    L.append("-- ⑦ ★★ LeaderTraits：能力 —— 【2 个城邦一组共用同一个官方 Trait】")
    L.append("--    这就是「能力重复但名字不同」：不同文明/领袖，同一个 Trait")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('%s', '%s');" % (leader(n), trait))
    L.append("")
    return "\n".join(L)


def gen_picker_sql():
    L = []
    L.append("-- ===========================================================================")
    L.append("-- 城邦缔造者 —— CityStates 表（配置库）")
    L.append("-- ★ 照工坊 3591345334 的 Picker.sql：通用 + XP1 + XP2 三个域各一条")
    L.append("-- 没有这张表 → 城邦面板显示 unknownType、加成文案空白")
    L.append("-- ===========================================================================")
    L.append("")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)")
        L.append("VALUES ('%s', '%s', 'LOC_CSF_CS_%s_NAME', '%s', 'LOC_CSF_CS_%s_BONUS');" % (civ(n), cat, n, icon, n))
        L.append("")
        for dom in ("Expansion1CityStates", "Expansion2CityStates"):
            L.append("INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)")
            L.append("VALUES ('%s', '%s', '%s', 'LOC_CSF_CS_%s_NAME', '%s', 'LOC_CSF_CS_%s_BONUS');" % (dom, civ(n), cat, n, icon, n))
            L.append("")
    return "\n".join(L)


def gen_colors_sql():
    L = []
    L.append("-- ===========================================================================")
    L.append("-- 城邦缔造者 —— PlayerColors（配置库）")
    L.append("-- ★★★ 这是我们城邦【没有颜色】的根因：从来没写过这张表！")
    L.append("-- 照工坊 3591345334 的 Colors.sql：Usage='Minor'，颜色用【官方常量】")
    L.append("--   PrimaryColor   = COLOR_PLAYER_CITY_STATE_PRIMARY")
    L.append("--   SecondaryColor = COLOR_PLAYER_CITY_STATE_<类别>_SECONDARY")
    L.append("-- ===========================================================================")
    L.append("")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append("INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)")
        L.append("VALUES ('%s', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_%s_SECONDARY');"
                 % (civ(n), col))
    L.append("")
    return "\n".join(L)


def gen_config_xml():
    L = []
    L.append('<?xml version="1.0" encoding="utf-8"?>')
    L.append("<!-- 城邦缔造者 —— 城邦选择器参数（配置库）")
    L.append("     照工坊 3591345334 的 Config.xml：挂到 ConfigurationId=SelectCityStates，")
    L.append("     这样 6 个城邦会出现在开局的【官方城邦选择器】里。 -->")
    L.append("<GameInfo>")
    L.append("  <Parameters>")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append('    <Row ParameterId="%s" Name="LOC_CSF_CS_%s_NAME" '
                 'Description="LOC_CSF_CS_%s_DESC" Domain="bool" DefaultValue="0" '
                 'ConfigurationGroup="Map" ConfigurationId="%s" GroupId="MapOptions" SortIndex="9%s"/>'
                 % (leader(n), n, n, leader(n), n))
    L.append("  </Parameters>")
    L.append("  <ParameterDependencies>")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        L.append('    <Row ParameterId="%s" ConfigurationGroup="Map" '
                 'ConfigurationId="SelectCityStates" Operator="Equals" ConfigurationValue="1"/>' % leader(n))
    L.append("  </ParameterDependencies>")
    L.append("</GameInfo>")
    L.append("")
    return "\n".join(L)


BONUS_ZH = {"SCIENTIFIC": "派遣1位使者：首都和每座图书馆+1科技值。",
            "CULTURAL":   "派遣1位使者：首都和每座剧院广场+1文化值。",
            "TRADE":      "派遣1位使者：首都和每座商业中心+1金币。"}
BONUS_EN = {"SCIENTIFIC": "+1 Science from your Capital and every Library once you send 1 Envoy.",
            "CULTURAL":   "+1 Culture from your Capital and every Theater Square once you send 1 Envoy.",
            "TRADE":      "+1 Gold from your Capital and every Commercial Hub once you send 1 Envoy."}


def gen_text_xml():
    L = []
    L.append('<?xml version="1.0" encoding="utf-8"?>')
    L.append("<GameData>")
    L.append("  <LocalizedText>")
    for n, cn, en, trait, cat, col, icon in CITY_STATES:
        pairs = [
            ("NAME",   cn, en),
            ("DESC",   cn + "（自定义城邦）", en + " (custom city-state)"),
            ("ADJ",    cn, en),
            ("LEADER", cn + "执政官", en + " Archon"),
            ("CITY",   cn, en),
            ("BONUS",  BONUS_ZH[cat], BONUS_EN[cat]),
        ]
        for key, zh, e in pairs:
            L.append('    <Row Tag="LOC_CSF_CS_%s_%s" Language="zh_Hans_CN"><Text>%s</Text></Row>' % (n, key, zh))
            L.append('    <Row Tag="LOC_CSF_CS_%s_%s" Language="en_US"><Text>%s</Text></Row>' % (n, key, e))
    L.append("  </LocalizedText>")
    L.append("</GameData>")
    L.append("")
    return "\n".join(L)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "src"
    data = os.path.join(out, "Data")
    text = os.path.join(out, "Text")
    os.makedirs(data, exist_ok=True)
    os.makedirs(text, exist_ok=True)

    files = [
        (os.path.join(data, "CSF_CustomCityStates.sql"),      gen_gameplay_sql()),
        (os.path.join(data, "CSF_CityStatePicker.sql"),       gen_picker_sql()),
        (os.path.join(data, "CSF_CityStateColors.sql"),       gen_colors_sql()),
        (os.path.join(data, "CSF_CityStateConfig.xml"),       gen_config_xml()),
        (os.path.join(text, "CSF_CustomCityStates_Text.xml"), gen_text_xml()),
    ]
    for path, content in files:
        with open(path, "w", encoding="utf-8", newline="\r\n") as fh:
            fh.write(content)
        print("  %-46s %4d 行" % (os.path.relpath(path, out), content.count("\n") + 1))

    print()
    print("  城邦数: %d（%d 组共享能力）" % (len(CITY_STATES), len(CITY_STATES) // 2))
    print("  玩法库: Types %d + TypeProperties %d + Civilizations %d + CivilizationLeaders %d"
          % (len(CITY_STATES) * 2, len(CITY_STATES), len(CITY_STATES), len(CITY_STATES)))
    print("          + CityNames %d + Leaders %d + LeaderTraits %d"
          % (len(CITY_STATES), len(CITY_STATES), len(CITY_STATES)))
    print("  配置库: CityStates %d 条（3 域）+ PlayerColors %d 条"
          % (len(CITY_STATES) * 3, len(CITY_STATES)))


if __name__ == "__main__":
    main()
