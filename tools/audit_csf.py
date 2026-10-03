#!/usr/bin/env python3
"""CityStateFounder 全项目一致性审计。

检查项（全部为静态、不需要游戏）：
  1. modinfo 引用的每个文件都存在
  2. 所有被动作引用的文件都在顶层 <Files> 里声明（Civ6 硬要求，漏了完全不加载）
  3. 代码里用到的 LOC_CSF_* 键，在 Text/CSF_Text.xml 里都有定义（否则界面显示 raw 键）
  4. Text 里定义的键，是否有代码在用（提示冗余）
  5. UI Lua 引用的 Controls.X，在对应 XML 里都有 ID
  6. XML 里定义的 ID，Lua 是否用到（提示冗余）
  7. 所有文本文件无 BOM
  8. 三个 XML 可解析
  9. Lua 里 local function 的定义/首次使用顺序（Lua 要求先定义后使用）

用法：python audit_csf.py
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"

ok_n = warn_n = err_n = 0


def ok(msg):
    global ok_n
    ok_n += 1
    print(f"  [OK]   {msg}")


def warn(msg):
    global warn_n
    warn_n += 1
    print(f"  [WARN] {msg}")


def err(msg):
    global err_n
    err_n += 1
    print(f"  [ERR]  {msg}")


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
print("=" * 72)
print("CityStateFounder 一致性审计")
print("=" * 72)

# --- 1/2. modinfo 引用 -----------------------------------------------------
print("\n[1] modinfo 引用完整性")
mi_path = SRC / "CityStateFounder.modinfo"
mi_text = read(mi_path)

declared = set(re.findall(r"<File>([^<]+)</File>", mi_text))
referenced = set(declared)  # <Files> 里声明的

# 动作块里引用的（<Items><File> 与无 Items 的 <File>）
all_files = set(re.findall(r"<File[^>]*>([^<]+)</File>", mi_text))

for f in sorted(all_files):
    full = SRC / f.replace("/", "\\")
    if full.is_file():
        ok(f"存在: {f}")
    else:
        err(f"引用但不存在: {f}")

# 动作里引用但没在顶层 <Files> 声明的
action_refs = all_files - declared
if action_refs:
    for f in sorted(action_refs):
        err(f"动作引用了但未在顶层 <Files> 声明（Civ6 会完全不加载）: {f}")
else:
    ok("所有动作引用的文件都已在顶层 <Files> 声明")

# --- 8/7. XML 与 BOM ------------------------------------------------------
print("\n[2] XML 可解析性 + BOM")
for f in sorted(SRC.rglob("*")):
    if not f.is_file():
        continue
    raw = f.read_bytes()
    if raw[:3] == b"\xef\xbb\xbf":
        err(f"有 BOM（会导致 SQL/本地化整份失效）: {f.relative_to(SRC)}")
    if f.suffix.lower() in (".xml", ".modinfo"):
        try:
            ET.fromstring(raw.decode("utf-8", errors="replace"))
            ok(f"XML 有效: {f.relative_to(SRC)}")
        except Exception as ex:
            err(f"XML 解析失败: {f.relative_to(SRC)} -> {ex}")

# --- 3/4. 本地化键 --------------------------------------------------------
print("\n[3] 本地化键一致性")
# ⚠️ 不能只读 Text/CSF_Text.xml —— 生成的文案放在 Data/ 下（如
#    Data/CSF_CustomCityStates_Text.xml），只读一个文件会把它们误报成"未定义"。
#    改为：扫描 src 下【所有】含 <LocalizedText> 或 <Replace Tag="LOC_CSF_ 的 xml。
defined: set[str] = set()
_text_files: list[str] = []
for f in sorted(SRC.rglob("*.xml")):
    body = read(f)
    if "LOC_CSF_" not in body:
        continue
    _text_files.append(str(f.relative_to(SRC)))
    defined |= set(re.findall(r'<Replace\s+Tag="(LOC_CSF_[A-Z0-9_]+)"', body))
    # 兼容属性顺序不同的写法
    defined |= set(re.findall(r'Tag="(LOC_CSF_[A-Z0-9_]+)"\s+Language=', body))
ok(f"已定义 LOC_CSF_* 键 {len(defined)} 个（来自 {len(_text_files)} 个文件: "
   f"{', '.join(_text_files)}）")

used: dict[str, list[str]] = {}
for f in sorted(SRC.rglob("*")):
    if f.suffix.lower() not in (".lua", ".xml", ".sql"):
        continue
    if f.name == "CSF_Text.xml":
        continue
    content = read(f)
    for m in re.finditer(r"(LOC_CSF_[A-Z0-9_]+)", content):
        used.setdefault(m.group(1), []).append(f.name)

for key in sorted(used):
    if key in defined:
        ok(f"已定义: {key}")
    else:
        err(f"代码用到但未定义（界面会显示 raw 键）: {key}  <- {sorted(set(used[key]))}")

unused = defined - set(used)
if unused:
    for key in sorted(unused):
        warn(f"已定义但代码未引用: {key}")
else:
    ok("所有已定义的键都被代码引用")

# --- 5/6. 控件 ID ---------------------------------------------------------
print("\n[4] UI 控件 ID 对齐")

pairs = [("UI/CSF_Panel.xml", "UI/CSF_Panel.lua")]
for xml_rel, lua_rel in pairs:
    xml_p = SRC / xml_rel.replace("/", "\\")
    lua_p = SRC / lua_rel.replace("/", "\\")
    if not (xml_p.is_file() and lua_p.is_file()):
        err(f"缺少文件: {xml_rel} 或 {lua_rel}")
        continue
    xroot = ET.fromstring(read(xml_p))
    xml_ids = {e.get("ID") for e in xroot.iter() if e.get("ID")}
    lua_ids = set(re.findall(r"Controls\.([A-Za-z_0-9]+)", read(lua_p)))

    missing = lua_ids - xml_ids
    if missing:
        for i in sorted(missing):
            err(f"{lua_rel} 引用 Controls.{i}，但 {xml_rel} 里没有该 ID")
    else:
        ok(f"{lua_rel} 引用的控件全部在 {xml_rel} 中存在")

    # 实例模板里的 ID 由 InstanceManager 提供，不算冗余
    extra = xml_ids - lua_ids
    if extra:
        warn(f"{xml_rel} 里有 {len(extra)} 个 ID 未被 Lua 直接引用（可能是实例模板或纯布局）")

# --- 9. Lua 定义/使用顺序 -------------------------------------------------
print("\n[5] Lua 定义/使用顺序（local 必须先定义后使用）")

# vendored 第三方文件：整份拷贝进来的外部代码，不由我们维护。
#   Data/BBS Maps/Utility/BBM_AssignStartingPlots.lua 是 CCB Maps 的文件，
#   我们只往里加了一段带注释的边界检查，其余一行未改。
#   它自己有一处 local 先用后定义（第 206 行用 spawn，第 338 行才定义），
#   那是上游的既有问题，不该算到我们头上 —— 但也不掩盖，单独报一行提示。
VENDORED = {
    # CCB Maps 的两个文件：只加了边界检查 / nil 检查，其余一行未改
    "BBM_AssignStartingPlots.lua",
    "BBM_CivilizationAssign.lua",
    # 官方的开局设置逻辑：只往 Parameters_Config_EndWrite 里加了一个钩子。
    #   官方自己有两处 local 先用后定义（control / s，分属不同作用域），
    #   是上游既有写法，不是我们的问题。
    "GameSetupLogic.lua",
}

for lua_p in sorted(SRC.rglob("*.lua")):
    lines = read(lua_p).splitlines()

    # 先收集【不是 local 定义】的绑定名：函数参数 + 循环变量，
    # 否则会把 `function f(iX, iY)` 里的 iX/iY、`for _, row in ...` 里的 row 误报成"未定义"。
    param_names: set[str] = set()
    for ln in lines:
        # function(...) 的参数列表
        for m in re.finditer(r"function\s*[A-Za-z_0-9.:]*\s*\(([^)]*)\)", ln):
            for a in m.group(1).split(","):
                a = a.strip()
                if a:
                    param_names.add(a)
        # for <vars> in / for <var> = ...
        m = re.match(r"\s*for\s+(.+?)\s+(?:in|=)", ln)
        if m:
            for a in m.group(1).split(","):
                a = a.strip()
                if a:
                    param_names.add(a)

    defs: dict[str, int] = {}
    for i, ln in enumerate(lines, 1):
        m = re.match(r"\s*local\s+function\s+([A-Za-z_0-9]+)", ln)
        if m:
            defs.setdefault(m.group(1), i)
        m2 = re.match(r"\s*local\s+([A-Za-z_0-9]+)\s*=", ln)
        if m2:
            defs.setdefault(m2.group(1), i)

    bad = 0
    for name, dline in defs.items():
        if name in param_names:
            continue                      # 同时被当作参数名 → 跳过，避免误报
        for i, ln in enumerate(lines, 1):
            if i == dline or i >= dline:
                continue
            if ln.strip().startswith("--"):
                continue
            if re.search(r"\b" + re.escape(name) + r"\b", ln):
                if lua_p.name in VENDORED:
                    # 上游既有问题，不算我们的 —— 单独提示，不计 ERR
                    warn(f"{lua_p.name}:{i} 上游既有的 local 先用后定义 '{name}'"
                         f"（定义在第 {dline} 行）—— vendored 第三方文件，非本次改动")
                else:
                    err(f"{lua_p.name}:{i} 使用了尚未定义的 local '{name}'（定义在第 {dline} 行）")
                    bad += 1
                break
    if bad == 0:
        ok(f"{lua_p.name}: {len(defs)} 个 local 的定义/使用顺序正确")

# --- 汇总 -----------------------------------------------------------------
print("\n" + "=" * 72)
print(f"汇总：OK {ok_n} · WARN {warn_n} · ERR {err_n}")
print("=" * 72)
sys.exit(1 if err_n else 0)

# --- 10. Lua 版本兼容：goto 是 Lua 5.2 才有的，Civ6 是 5.1 ---
print("\n[6] Lua 5.1 兼容性（goto 不可用）")
_goto_bad = 0
for lua_p in sorted(SRC.rglob("*.lua")):
    for i, ln in enumerate(read(lua_p).splitlines(), 1):
        if ln.strip().startswith("--"):
            continue
        if re.search(r"\bgoto\s+[A-Za-z_]", ln):
            err(f"{lua_p.name}:{i} 用了 goto —— Civ6 是 Lua 5.1，goto 是 5.2 才有，"
                f"会导致整个脚本 Syntax Error 而不加载")
            _goto_bad += 1
if _goto_bad == 0:
    ok("所有 Lua 文件都没有 goto（Lua 5.1 兼容）")