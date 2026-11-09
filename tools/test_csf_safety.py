#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_csf_safety.py —— CSF 建邦安全性的【离线】回归测试

它做两件事，都指向"改完之后真的不再假成功"：

  [A] 注册回归（静态，覆盖任务1）
      解析 src/CityStateFounder.modinfo 的 XML【元素树】（注释不进树），
      确认开局数量实验与两个 BBM 覆盖脚本已经【没有任何可执行引用】：

        - 没有 id 以 CSF_EXP_ / CSF_CCB_FIX_ 开头的动作
        - 元素文本里不再出现 AdvancedSetup.lua / BBM_AssignStartingPlots.lua /
          BBM_CivilizationAssign.lua（含顶层 Files 列表）

  [B] 行为回归（真实 Lua 运行时，覆盖任务2）
      用 lupa（内建 Lua 5.5）在受控桩环境里装载 **真实的**
      src/Lua/CSF_Gameplay.lua 与 src/Lua/CSF_CreateCityState.lua，
      调用它们真实的函数，检查返回码 / 引擎调用次数 / 存档属性 / UI 广播。

      这不是字符串断言：桩里的 Players、Map、UnitManager、C6FW、
      WorldBuilder 都是可编程的假引擎，能精确制造"原生激活失败""Create 抛错"
      "静默 0 城""别处有城而目标格没城"等场景。

用法：
    python tools/test_csf_safety.py [-v]

退出码：0 = 全部通过；1 = 有失败；2 = 环境缺失（没有可用的 Lua runtime 等）
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SRC = ROOT / "src"
MODINFO = SRC / "CityStateFounder.modinfo"
GAMEPLAY = SRC / "Lua" / "CSF_Gameplay.lua"
CREATE = SRC / "Lua" / "CSF_CreateCityState.lua"
HARNESS = HERE / "test_csf_safety_harness.lua"

FORBIDDEN_ACTIVE = (
    "AdvancedSetup.lua",
    "BBM_AssignStartingPlots.lua",
    "BBM_CivilizationAssign.lua",
    "CSF_DuplicateCityStates.sql",
)
FORBIDDEN_ID_PREFIX = ("CSF_EXP_", "CSF_CCB_FIX_", "CSF_DuplicateCityStates")

# 摘除实验注册后应当剩下的动作集合（精确比对，防止误删正常注册）
EXPECTED_FE = (
    # v1.0.6 intentionally bundles XP2; scope is independently checked with
    # real SQLite and negative variants in test_portable_registration.py.
    ("UpdateDatabase", "CSF_Bundled_GameCore"),
    ("UpdateText", "CSF_Text_FE"),
    ("UpdateDatabase", "CSF_MapSizes"),
    ("UpdateIcons", "CSF_Icons_FE"),
    ("UpdateDatabase", "CSF_CityStateConfig"),
    ("UpdateText", "CSF_CustomCityStates_Text_FE"),
)
EXPECTED_IG = (
    ("UpdateDatabase", "CSF_Units"),
    ("UpdateDatabase", "CSF_CustomCityStates"),
    ("UpdateDatabase", "CSF_CityStateColors"),
    ("UpdateText", "CSF_Text_IG"),
    ("UpdateText", "CSF_CustomCityStates_Text_IG"),
    ("UpdateIcons", "CSF_Icons_IG"),
    ("AddGameplayScripts", "CSF_Gameplay"),
    ("AddGameplayScripts", "CSF_CreateCityState"),
    ("ImportFiles", "CSF_UI_IMPORT"),
    ("AddUserInterfaces", "CSF_UI"),
    ("ImportFiles", "CSF_UNITPANEL_IMPORT"),
    ("ReplaceUIScript", "CSF_REPLACE_UNITPANEL"),
    ("ReplaceUIScript", "CSF_REPLACE_CITYBANNER"),
    ("ReplaceUIScript", "CSF_REPLACE_CITYSTATES"),
    ("ReplaceUIScript", "CSF_REPLACE_UNITFLAG"),
    ("ImportFiles", "CSF_UI_COMMON_IMPORT"),
    ("ImportFiles", "CSF_BANNER_IMPORT"),
    ("ImportFiles", "CSF_CITYSTATES_IMPORT"),
)

# 由 harness 打印、本脚本解析的协议行
RE_RESULT = re.compile(r"^RESULT\|(?P<name>.+?)\|(?P<status>PASS|FAIL)\|(?P<detail>.*)$")
RE_TOTAL = re.compile(r"^TOTAL\|(\d+)$")
RE_FAILED = re.compile(r"^FAILED\|(\d+)$")

# 【对照组】修改前的原件上，这些断言【必须】失败 —— 否则说明夹具没有判别力
# （它们正是"把失败报成成功"的具体证据）。用 --baseline <原件目录> 验证。
MUST_FAIL_ON_BASELINE = (
    "T1.3 开局不额外造城邦（无 InitUnit）",
    "T3b.2 原因 = set_alive_failed",
    "T3c.1 补色失败不返回成功",
    "T4.2 原因 = create_threw",
    "T5.1 静默 0 城不返回成功",
    "T6.1 别处有城但目标格没城 → 不返回成功",
    "T8.3 失败后同回合重试不被 'one_per_turn' 挡",
    "T11.1 城市数变了但目标格没城 → 不返回成功",
)


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8", errors="replace").splitlines())


# ---------------------------------------------------------------- [A] 注册回归
def check_modinfo_registration(modinfo: Path | None = None) -> tuple[list[tuple[str, bool, str]], str]:
    """返回 (结果列表, 摘要文本)。解析的是 XML 元素树，注释天然被忽略。"""
    modinfo = modinfo or MODINFO
    out: list[tuple[str, bool, str]] = []

    try:
        tree = ET.parse(modinfo)
    except ET.ParseError as exc:
        out.append(("modinfo XML 可解析", False, f"ET.ParseError: {exc}"))
        return out, "解析失败"
    root = tree.getroot()
    out.append(("modinfo XML 可解析", True, f"root={root.tag} id={root.get('id')}"))

    # 所有动作 id
    ids = [(el.tag, el.get("id") or "") for el in root.iter()]
    bad_ids = [(t, i) for (t, i) in ids if any(i.startswith(p) for p in FORBIDDEN_ID_PREFIX)]
    out.append((
        "无实验动作注册（id 不以 "
        + " / ".join(FORBIDDEN_ID_PREFIX) + " 开头）",
        not bad_ids,
        "命中=" + repr(bad_ids) if bad_ids else "无",
    ))

    # 所有元素的文本（涵盖 <File> / <LuaReplace> / <Items><File> 等所有写法）
    texts = [(el.tag, (el.text or "").strip()) for el in root.iter() if (el.text or "").strip()]
    hits = [(t, x) for (t, x) in texts if any(f in x for f in FORBIDDEN_ACTIVE)]
    out.append((
        "没有可执行引用指向开局实验、BBM 覆盖或旧副本白名单",
        not hits,
        "命中=" + repr(hits) if hits else "无（含顶层 Files 列表）",
    ))

    # 被摘掉的三条必须确实不在 Files 列表里
    file_texts = {
        (el.text or "").strip().replace("\\", "/")
        for el in root.iter()
        if el.tag in ("File", "LuaReplace", "LuaContext")
    }
    still_listed = sorted(file_texts & set(FORBIDDEN_ACTIVE))
    out.append((
        "顶层 Files / 动作引用里不再列出已撤下文件",
        not still_listed,
        "仍列出=" + repr(still_listed) if still_listed else "已全部摘除",
    ))

    # 保留动作必须精确等于预期集合（防止误删正常注册）
    def _ids(sec_name: str) -> tuple[tuple[str, str], ...]:
        sec = root.find(sec_name)
        if sec is None:
            return ()
        return tuple((k.tag, k.get("id") or "") for k in sec)

    got_fe = _ids("FrontEndActions")
    got_ig = _ids("InGameActions")
    out.append((
        "FrontEndActions 动作集合未被误改",
        got_fe == EXPECTED_FE,
        f"缺失={sorted(set(EXPECTED_FE) - set(got_fe))} 多余={sorted(set(got_fe) - set(EXPECTED_FE))}",
    ))
    out.append((
        "InGameActions 动作集合未被误改（实验+BBM 覆盖已摘除）",
        got_ig == EXPECTED_IG,
        f"缺失={sorted(set(EXPECTED_IG) - set(got_ig))} 多余={sorted(set(got_ig) - set(EXPECTED_IG))}",
    ))

    # UI include closure: a local file referenced by include() must be imported
    # into the VFS by some ImportFiles action.  Top-level <Files> alone is not
    # sufficient for the filename lookup used by Civ6 UI contexts.
    import_items = {
        (el.text or "").strip().replace("\\", "/")
        for action in root.findall("InGameActions/ImportFiles")
        for el in action.iter("File")
        if (el.text or "").strip()
    }
    local_names = {p.name for p in (SRC / "UI").glob("*.lua")}
    missing_includes: list[tuple[str, str]] = []
    include_re = re.compile(r"include\s*\(\s*[\"']([^\"']+)[\"']\s*\)")
    for source in (SRC / "UI").glob("*.lua"):
        text = source.read_text(encoding="utf-8", errors="replace")
        for target in include_re.findall(text):
            target_file = target if target.lower().endswith(".lua") else target + ".lua"
            if Path(target_file).name in local_names and ("UI/" + Path(target_file).name) not in import_items:
                missing_includes.append((source.name, target_file))
    out.append((
        "UI 本地 include 文件均已通过 ImportFiles 导入",
        not missing_includes,
        "缺失=" + repr(sorted(set(missing_includes))) if missing_includes else "闭包完整",
    ))

    replacement_missing: list[str] = []
    for el in root.findall("InGameActions/ReplaceUIScript"):
        target = el.findtext("Properties/LuaReplace") or ""
        if target and target.replace("\\", "/") not in import_items:
            replacement_missing.append(target)
    out.append((
        "每个 ReplaceUIScript 目标均被 ImportFiles 导入",
        not replacement_missing,
        "缺失=" + repr(replacement_missing) if replacement_missing else "目标均已导入",
    ))

    summary = f"FrontEnd={len(got_fe)} InGame={len(got_ig)}；禁用文件引用命中={len(hits)}"
    return out, summary


# ------------------------------------------------------- [B] 真实 Lua 运行时回归
def run_lua_harness(
    verbose: bool,
    gameplay: Path | None = None,
    create: Path | None = None,
) -> tuple[list[tuple[str, bool, str]], str, list[str]]:
    """用 lupa 跑 harness。返回 (结果列表, 摘要, 原始输出行)。"""
    gameplay = gameplay or GAMEPLAY
    create = create or CREATE
    try:
        import lupa
    except ImportError:
        raise RuntimeError(
            "没有可用的 Lua runtime：Python 包 lupa 未安装。\n"
            "  安装：python -m pip install lupa\n"
            "  本项目所在机器的既有环境为 lupa 2.8（内建 Lua 5.5）。"
        )

    for p in (gameplay, create, HARNESS):
        if not p.is_file():
            raise RuntimeError(f"缺少文件：{p}")

    captured: list[str] = []

    def lua_print(*args):
        parts = []
        for a in args:
            if isinstance(a, (bytes, bytearray)):
                a = bytes(a).decode("utf-8", "replace")
            parts.append(str(a))
        captured.append(" ".join(parts))

    # encoding=None：Lua 字符串按字节传给 Python，我们自己做【宽容】解码。
    # 必要性：夹具里的日志截断（string.sub 按字节切）可能把中文 UTF-8 字符切一半，
    # 严格 utf-8 解码会直接抛 UnicodeDecodeError 把整个 harness 打断。
    lua = lupa.LuaRuntime(encoding=None)
    lua_version = lua.eval("_VERSION")
    if isinstance(lua_version, (bytes, bytearray)):
        lua_version = bytes(lua_version).decode("utf-8", "replace")
    lua_version = str(lua_version)
    lua.globals().print = lua_print
    lua.globals().CSF_SRC_DIR = str(SRC).replace("\\", "/").encode("utf-8")
    lua.globals().CSF_LUA_GAMEPLAY = str(gameplay).replace("\\", "/").encode("utf-8")
    lua.globals().CSF_LUA_CREATE = str(create).replace("\\", "/").encode("utf-8")

    try:
        lua.execute(HARNESS.read_text(encoding="utf-8").encode("utf-8"))
    except Exception as exc:  # lupa.LuaError
        tail = "\n".join(f"  | {x}" for x in captured[-40:])
        raise RuntimeError(
            f"harness 执行中断（{type(exc).__name__}）：{exc}\n"
            f"  最近输出：\n{tail}"
        ) from exc

    results: list[tuple[str, bool, str]] = []
    total = failed = None
    last_idx: int | None = None
    for line in captured:
        m = RE_RESULT.match(line)
        if m:
            results.append((m.group("name"), m.group("status") == "PASS", m.group("detail")))
            last_idx = len(results) - 1
            continue
        if RE_TOTAL.match(line):
            total = int(RE_TOTAL.match(line).group(1))
            continue
        if RE_FAILED.match(line):
            failed = int(RE_FAILED.match(line).group(1))
            continue
        if last_idx is not None and line.strip():
            # 详情里万一夹了换行，接回上一条而不是丢掉（否则计数会对不上）
            name, ok, detail = results[last_idx]
            results[last_idx] = (name, ok, detail + " ⏎ " + line.strip())
            continue
        if verbose:
            print(f"    (lua) {line}")

    if not results:
        raise RuntimeError(
            "harness 没有产出任何 RESULT 行 —— 夹具未真正跑起来。原始输出：\n  "
            + "\n  ".join(captured[-40:])
        )

    if total is not None and total != len(results):
        results.append((f"协议一致性：TOTAL={total} 但实际收到 {len(results)} 条", False, "计数不符"))
    if failed is not None:
        n_fail = sum(1 for _, ok, _ in results if not ok)
        if failed != n_fail:
            results.append((f"协议一致性：FAILED={failed} 但实际失败 {n_fail} 条", False, "计数不符"))

    summary = f"{lua_version}（lupa {getattr(lupa, '__version__', '?')}）· {len(results)} 项断言"
    return results, summary, captured


# ---------------------------------------------------------------------- 报告输出
def print_section(title: str) -> None:
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


def print_results(results: list[tuple[str, bool, str]]) -> int:
    n_fail = 0
    for name, ok, detail in results:
        if ok:
            print(f"  [PASS] {name}")
        else:
            n_fail += 1
            print(f"  [FAIL] {name}")
            print(f"         → {detail}")
    return n_fail


def run_baseline(baseline: Path, verbose: bool) -> int:
    """【对照组】拿修改前的原件跑同一套断言。

    期望：修改前的代码在 MUST_FAIL_ON_BASELINE 那些断言上【失败】——
    这才是"夹具真的有判别力"的证据（否则整套测试等于怎么改都过）。
    """
    print_section(f"[对照] 用修改前的原件跑同一套断言： {baseline}")

    b_modinfo = baseline / "CityStateFounder.modinfo"
    b_gameplay = baseline / "Lua" / "CSF_Gameplay.lua"
    b_create = baseline / "Lua" / "CSF_CreateCityState.lua"
    for p in (b_modinfo, b_gameplay, b_create):
        if not p.is_file():
            print(f"  [FATAL] 找不到原件 {p}")
            return 2
        print(f"  {sha256_of(p)}  {p.name:<28} {line_count(p):>5} 行")

    bad = 0

    # ---------------- 注册：原件上应当还能看到实验/BBM 覆盖注册 ----------------
    print()
    print("  --- 任务1 注册断言：原件上必须仍能看到实验/BBM 覆盖注册 ---")
    reg_results, reg_summary = check_modinfo_registration(b_modinfo)
    n_reg_fail = 0
    for name, ok, detail in reg_results:
        if not ok:
            n_reg_fail += 1
            print(f"    [FAIL] {name}")
            print(f"           → {detail}")
    print(f"    —— {reg_summary}；失败 {n_reg_fail}/{len(reg_results)}")
    if n_reg_fail == 0:
        print("    ⚠️ 原件上注册断言全部通过 —— 任务1 的断言没有判别力！")
        bad += 1

    # ---------------- 行为：原件上必须出现"失败被报成成功" ----------------
    print()
    print("  --- 任务2 行为断言：原件上必须出现失败被报成成功 ---")
    try:
        results, summary, _ = run_lua_harness(verbose, gameplay=b_gameplay, create=b_create)
    except RuntimeError as exc:
        print(f"  [FATAL] {exc}")
        return 2
    for name, ok, detail in results:
        if not ok:
            print(f"    [FAIL] {name}")
            print(f"           → {detail}")
    failed_names = {name for name, ok, _ in results if not ok}
    print(f"    —— 运行时： {summary}")
    print(f"    —— 原件上失败断言： {len(failed_names)}/{len(results)}")

    print()
    print("  --- 判别力核对：下列断言在原件上【必须】失败 ---")
    missing = []
    for n in MUST_FAIL_ON_BASELINE:
        if n in failed_names:
            print(f"    ✓ 已失败   {n}")
        else:
            print(f"    ✗ 竟通过   {n}")
            missing.append(n)
    if missing:
        print()
        print("  [FAIL] 下列断言在修改前的原件上居然也通过 → 夹具没有判别力：")
        for n in missing:
            print(f"         - {n}")
        return 1
    if bad:
        return 1
    print()
    print("  结论：对照组符合预期 —— 夹具确实抓住了修改前的问题（不是空断言）。")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true", help="同时打印 Lua 侧日志")
    ap.add_argument(
        "--baseline",
        metavar="DIR",
        help="对照组模式：用修改前的原件（DIR 下 CityStateFounder.modinfo 与 Lua/*.lua）"
             "跑同一套断言，验证夹具具备判别力",
    )
    args = ap.parse_args()

    if args.baseline:
        return run_baseline(Path(args.baseline), args.verbose)

    print("CSF 建邦安全性离线回归 —— CityStateFounder")
    print(f"项目根： {ROOT}")

    # ---------------- 源文件指纹（证明测的是磁盘上真实的被测文件） ----------------
    print_section("[0] 被测源文件指纹（SHA256）")
    for p in (MODINFO, GAMEPLAY, CREATE, HARNESS):
        if not p.is_file():
            print(f"  [FAIL] 缺少文件 {p}")
            return 2
        try:
            rel = p.relative_to(ROOT)
        except ValueError:
            rel = p
        print(f"  {sha256_of(p)}  {str(rel):<46} {line_count(p):>5} 行")

    all_results: list[tuple[str, bool, str]] = []

    # ---------------- [A] 注册回归 ----------------
    print_section("[A] 任务1 注册回归（解析 modinfo 元素树；注释不算引用）")
    reg_results, reg_summary = check_modinfo_registration()
    print_results(reg_results)
    print(f"  —— {reg_summary}")
    all_results += reg_results

    # ---------------- [B] 行为回归 ----------------
    print_section("[B] 任务2 行为回归（lupa 载入真实 Lua 脚本 + 受控桩引擎）")
    try:
        beh_results, beh_summary, captured = run_lua_harness(args.verbose)
    except RuntimeError as exc:
        print(f"  [FATAL] {exc}")
        return 2
    print_results(beh_results)
    print(f"  —— 运行时： {beh_summary}")
    all_results += beh_results

    # ---------------- 汇总 ----------------
    n_fail = sum(1 for _, ok, _ in all_results if not ok)
    print_section("汇总")
    print(f"  断言总数： {len(all_results)}")
    print(f"  通过：     {len(all_results) - n_fail}")
    print(f"  失败：     {n_fail}")
    if n_fail:
        print()
        print("  失败的断言：")
        for name, ok, detail in all_results:
            if not ok:
                print(f"    - {name}  ({detail})")
        print()
        print("  结论：未通过 —— 仍有假成功或注册残留。")
        return 1
    print()
    print("  结论：离线注册与受控 Lua 行为断言全部通过；不代表游戏全生命周期验收。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
