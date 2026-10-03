# -*- coding: utf-8 -*-
"""把用户确认的文案改动写进 workshop.json / modinfo / 本地化文件。"""
import json, io, sys, re, os

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = r"D:\A-Developing\main\civ6\A-C6-Mod"
WS = os.path.join(ROOT, "_workshop_workspaces", "CityStateFounder", "workshop.json")
MODINFO = os.path.join(ROOT, "CityStateFounder", "src", "CityStateFounder.modinfo")
TEXT = os.path.join(ROOT, "CityStateFounder", "src", "Text", "CSF_Text.xml")

DESC_ZH = (
    "[h1]城邦缔造者[/h1]\n\n"
    "新增一个单位，让你[b]随心所欲建建邦[/b]。\n\n"
    "[hr][/hr]\n\n"
    "[h2]单位[/h2]\n"
    "[b]建邦使节[/b] —— 150 生产力，平民单位，陆地。\n"
    "[b]不可[/b]建立普通城市，使用后所在单元格[b]出现一名城邦的开拓者[/b]。\n\n"
    "[h2]怎么用[/h2]\n"
    "[list]\n"
    "[*]把建邦使节移动到你想让城邦出现的位置。\n"
    "[*]打开单位面板，点[b]建立城邦[/b]。\n"
    "[*]面板会列出本局可用的每一个城邦 —— 图标、名称、宗主加成。\n"
    "[*]选一个并确认。该城邦的移民会就位，并在它自己的回合建城。\n"
    "[/list]\n\n"
    "[h2]你会得到什么[/h2]\n"
    "[list]\n"
    "[*]这是一个[b]引擎层面的真城邦[/b] —— 颜色、名称、使者、宗主加成、任务全部正常。\n"
    "[*][b]AI 独立城邦，不属于你[/b]。\n"
    "[*]作为缔造者，你获得[b]1 个使者[/b]。\n"
    "[*]与原生城邦界面、以及各类城邦相关 MOD 兼容。\n"
    "[/list]\n\n"
    "[h2]能建几个？[/h2]\n"
    "除了地图上正常存在的城邦，本模组还会[b]把额外一批城邦隐藏起来[/b]供你建立。\n"
    "建议的城邦数量（开局设置里的滑条）：\n\n"
    "[list]\n"
    "[*]决斗 —— 默认 4，最高 9\n"
    "[*]极小 —— 默认 9，最高 15\n"
    "[*]小 —— 默认 13，最高 21\n"
    "[*][b]标准 —— 默认 18，最高 27[/b]\n"
    "[*]大 —— 默认 22，最高 33\n"
    "[*]巨大 —— 默认 27，最高 36\n"
    "[/list]\n\n"
    "本模组会把上限抬高到官方值的 1.5 倍，默认值也同步抬高（官方默认的 1.5 倍）。\n"
    "[b]按默认值开局[/b]，你的地图上会有约三分之二的城邦正常运作，其余三分之一处于休眠状态、等你建立。\n"
    "想要更多可建名额，把滑条往上拉即可。\n\n"
    "[h2]地图 MOD 兼容性[/h2]\n"
    "[list]\n"
    "[*][b]完全兼容 CCB 地图（Better Balanced Maps）[/b] —— 已针对它做过适配，可放心一同使用。\n"
    "[*]与原版地图脚本（大陆、泛大陆、地球等）[b]完全兼容[/b]，一个文件都没有改动。\n"
    "[*]与其他地图 MOD [b]不冲突[/b] —— 本模组只覆盖了 CCB 独有的两个文件，其他地图 MOD 没有这两个文件。\n"
    "[/list]\n\n"
    "[h2]说明[/h2]\n"
    "[list]\n"
    "[*]需要[b]风云变幻[/b]（模组在风云变幻规则集下加载）。\n"
    "[*][b]AI 不会使用「建邦使节」[/b] —— 这是玩家专属的能力。\n"
    "[*]单机可用，未测试联机。\n"
    "[*]可加入已有存档，但城邦是在开局时预留的，所以已经开始的对局可建数量会较少。\n"
    "[/list]\n\n"
    "[h2]反馈[/h2]\n"
    "[list]\n"
    "[*]创意工坊留言\n"
    "[*]MOD 反馈群：1105479995\n"
    "[*]个人 QQ：1600597561\n"
    "[/list]"
)

DESC_EN = (
    "[h1]City-State Founder[/h1]\n\n"
    "Adds a unit that lets [b]you[/b] found City-States wherever you like.\n\n"
    "[hr][/hr]\n\n"
    "[h2]The unit[/h2]\n"
    "[b]City-State Envoy[/b] — 150 production, civilian, land.\n"
    "It [b]cannot[/b] found a normal city. Using it makes a [b]City-State Settler appear on its tile[/b].\n\n"
    "[h2]How it works[/h2]\n"
    "[list]\n"
    "[*]Move the Envoy to the tile where you want the City-State to appear.\n"
    "[*]Open the unit panel and click [b]Found City-State[/b].\n"
    "[*]A panel lists every City-State available in this game — icon, name and suzerain bonus.\n"
    "[*]Pick one and confirm. A Settler of that City-State moves in and it founds its city on its own turn.\n"
    "[/list]\n\n"
    "[h2]What you get[/h2]\n"
    "[list]\n"
    "[*]A [b]real engine City-State[/b] — normal colours, name, envoys, suzerain bonus and quests.\n"
    "[*][b]An AI City-State, independent of you.[/b]\n"
    "[*]You gain [b]1 Envoy[/b] with it as the founder.\n"
    "[*]Works with the existing City-State UI and with City-State related mods.\n"
    "[/list]\n\n"
    "[h2]How many can I found?[/h2]\n"
    "Alongside the City-States normally on the map, this mod [b]keeps an extra batch hidden[/b] for you to found.\n"
    "Recommended counts (the slider in game setup):\n\n"
    "[list]\n"
    "[*]Duel — default 4, up to 9\n"
    "[*]Tiny — default 9, up to 15\n"
    "[*]Small — default 13, up to 21\n"
    "[*][b]Standard — default 18, up to 27[/b]\n"
    "[*]Large — default 22, up to 33\n"
    "[*]Huge — default 27, up to 36\n"
    "[/list]\n\n"
    "The ceiling is raised to one and a half times the original, and the default moves with it.\n"
    "Starting at the default leaves roughly two thirds of the City-States running on the map and the other third\n"
    "asleep, waiting for you to found them. Drag the slider up for more.\n\n"
    "[h2]Map mod compatibility[/h2]\n"
    "[list]\n"
    "[*][b]Fully compatible with CCB Maps (Better Balanced Maps)[/b] — adapted for it, safe to use together.\n"
    "[*][b]Fully compatible[/b] with the original map scripts (Continents, Pangaea, Earth and so on); not one of their files is touched.\n"
    "[*][b]No conflict[/b] with other map mods — this mod only replaces two files that are unique to CCB Maps.\n"
    "[/list]\n\n"
    "[h2]Notes[/h2]\n"
    "[list]\n"
    "[*]Requires [b]Gathering Storm[/b].\n"
    "[*][b]The AI never uses the City-State Envoy[/b] — it is a player-only ability.\n"
    "[*]Works in single player. Not tested in multiplayer.\n"
    "[*]Can be added to an existing save, but City-States are reserved at game start, so an already running save will have fewer available.\n"
    "[/list]\n\n"
    "[h2]Feedback[/h2]\n"
    "[list]\n"
    "[*]Workshop comments\n"
    "[*]MOD Feedback Group: 1105479995\n"
    "[*]Personal QQ: 1600597561\n"
    "[/list]"
)

TEASER_ZH = "随心所欲建建邦"
TEASER_EN = "Found City-States wherever you want."
MODDESC_ZH = ("新增「建邦使节」单位：不可建立普通城市，使用后原地召唤一个场上不存在的城邦。"
              "配套面板会列出本局可用的城邦（图标 / 名称 / 宗主加成）供你选择。")
MODDESC_EN = ("Adds the City-State Envoy unit. It cannot found a normal city - instead it summons a "
              "City-State that is not yet present on the map, right where it stands. A panel lists the "
              "City-States available in this game (icon / name / suzerain bonus) for you to choose from.")

# ── ① workshop.json ────────────────────────────────────────────────────────
with open(WS, encoding="utf-8") as fh:
    ws = json.load(fh)
ws["description"] = DESC_EN
for loc in ws.get("localizations", []):
    if loc.get("language") == "schinese":
        loc["title"] = "城邦缔造者"
        loc["description"] = DESC_ZH
ws["changeNote"] = "v1.0.0 — City-State Envoy unit and its founding panel; CCB Maps compatibility."
with open(WS, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(ws, fh, ensure_ascii=False, indent=2)
print("✅ workshop.json 已更新")
print("   中文标题:", [l["title"] for l in ws["localizations"] if l["language"] == "schinese"][0])
print("   中文字数:", len(DESC_ZH), " 英文字数:", len(DESC_EN))

# ── ② modinfo 的 <LocalizedText> ───────────────────────────────────────────
with open(MODINFO, encoding="utf-8") as fh:
    mi = fh.read()
mi = re.sub(r"(<Text id=\"LOC_CSF_MOD_TEASER\">\s*<en_US>)[^<]*(</en_US>\s*<zh_Hans_CN>)[^<]*(</zh_Hans_CN>)",
            lambda m: m.group(1) + TEASER_EN + m.group(2) + TEASER_ZH + m.group(3), mi)
mi = re.sub(r"(<Text id=\"LOC_CSF_MOD_DESCRIPTION\">\s*<en_US>)[^<]*(</en_US>\s*<zh_Hans_CN>)[^<]*(</zh_Hans_CN>)",
            lambda m: m.group(1) + MODDESC_EN + m.group(2) + MODDESC_ZH + m.group(3), mi)
with open(MODINFO, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(mi)
print("✅ modinfo 的 LocalizedText 已更新")

# ── ③ 本地化文件 ───────────────────────────────────────────────────────────
with open(TEXT, encoding="utf-8") as fh:
    tx = fh.read()
for tag, zh, en in (("LOC_CSF_MOD_TEASER", TEASER_ZH, TEASER_EN),
                    ("LOC_CSF_MOD_DESCRIPTION", MODDESC_ZH, MODDESC_EN)):
    tx = re.sub(r"(<Replace Tag=\"" + tag + r"\" Language=\"zh_Hans_CN\">)[^<]*(</Replace>)",
                lambda m: m.group(1) + zh + m.group(2), tx)
    tx = re.sub(r"(<Replace Tag=\"" + tag + r"\" Language=\"en_US\">)[^<]*(</Replace>)",
                lambda m: m.group(1) + en + m.group(2), tx)
with open(TEXT, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(tx)
print("✅ CSF_Text.xml 已更新")
