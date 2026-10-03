#!/usr/bin/env python3
"""从 Civ6 引擎二进制中提取 Lua 绑定（binding）方法名。

原理：Civ6 的 Lua 绑定注册表内嵌了每个接口的绑定源码路径字符串
（形如 "Lua_ICityManager.cpp"）。该字符串之后紧邻的就是该接口暴露给 Lua
的方法名字符串常量。据此可以**不启动游戏**就枚举出真实存在的 API。

这解决了「官方 Lua 没调用过 X」≠「引擎没有 X 绑定」的判定陷阱。

用法：
  python _tmp_bindings.py --list-interfaces
  python _tmp_bindings.py --iface ICityManager
  python _tmp_bindings.py --iface IPlayerManager IUnitManager IBarbarianTribes
  python _tmp_bindings.py --find CreateCity TransferCity AddPlayer CreateTribeOfType
  python _tmp_bindings.py --all --json out.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

GAME = Path(r"F:\Steam\steamapps\common\Sid Meier's Civilization VI")
BIN = GAME / "Base" / "Binaries" / "Win64Steam"

# 候选二进制（GameCore 是主战场，其余作交叉验证）
CANDIDATES = [
    "GameCore_Base_FinalRelease.dll",
    "GameCore_Expansion1_FinalRelease.dll",
    "GameCore_Expansion2_FinalRelease.dll",
    "CivilizationVI.exe",
    "CivilizationVI_DX12.exe",
]

ANCHOR_RE = re.compile(rb"Lua_I([A-Za-z0-9_]+)\.cpp")
WIN = 3000  # 锚点之后扫描的字节窗口


def load_strings(buf: bytes, minlen: int = 3) -> list[str]:
    """提取可打印 ASCII 串。"""
    out, cur = [], bytearray()
    for b in buf:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= minlen:
                out.append(cur.decode("ascii"))
            cur = bytearray()
    if len(cur) >= minlen:
        out.append(cur.decode("ascii"))
    return out


def ident_like(s: str) -> bool:
    """过滤出像 C++/Lua 方法名的串。"""
    if not (3 <= len(s) <= 48):
        return False
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", s):
        return False
    # 排除明显的噪声
    if s.startswith(("_", "std", "??", "0x")):
        return False
    return True


def scan(path: Path):
    data = path.read_bytes()
    hits: dict[str, list[str]] = {}
    for m in ANCHOR_RE.finditer(data):
        iface = m.group(1).decode("ascii")
        chunk = data[m.end(): m.end() + WIN]
        names = [s for s in load_strings(chunk) if ident_like(s)]
        # 去重保序
        seen, uniq = set(), []
        for n in names:
            if n not in seen:
                seen.add(n)
                uniq.append(n)
        hits.setdefault(iface, [])
        hits[iface].extend(uniq)
    # 全局去重
    for k in hits:
        seen, uniq = set(), []
        for n in hits[k]:
            if n not in seen:
                seen.add(n)
                uniq.append(n)
        hits[k] = uniq
    return data, hits


def scan_runs(path: Path):
    """按锚点区间切分：每个 Lua_IX.cpp 到下一个锚点之间的字符串 = 该接口的绑定名表。

    比固定窗口可靠得多——Lua_I*.cpp 锚点在字符串池里成簇排列，
    区间内的可打印串即该接口注册的方法名（HavokScript 的 luaL_Reg 顺序）。
    """
    data = path.read_bytes()
    anchors = [(m.start(), m.group(1).decode("ascii")) for m in ANCHOR_RE.finditer(data)]
    anchors.sort()
    runs: dict[str, list[str]] = {}
    for i, (off, iface) in enumerate(anchors):
        end = anchors[i + 1][0] if i + 1 < len(anchors) else off + WIN
        chunk = data[off:end]
        names = [s for s in load_strings(chunk, minlen=3) if ident_like(s)]
        seen, uniq = set(), []
        for n in names:
            if n not in seen:
                seen.add(n)
                uniq.append(n)
        # 去掉锚点自身
        uniq = [n for n in uniq if not n.startswith("Lua_I")]
        if uniq:
            runs[iface] = uniq
    return runs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dll", help="指定二进制（默认 GameCore_Base_FinalRelease.dll）")
    ap.add_argument("--list-interfaces", action="store_true")
    ap.add_argument("--runs", action="store_true", help="按锚点区间精确导出各接口方法表")
    ap.add_argument("--iface", nargs="*", help="打印这些接口的绑定窗口")
    ap.add_argument("--find", nargs="*", help="在这些二进制里全局搜索字符串")
    ap.add_argument("--names", help="从 DLL 全量字符串里按正则筛选标识符名（如 'City' 'Player' 'Tribe'）")
    ap.add_argument("--all", action="store_true", help="导出全部接口")
    ap.add_argument("--json", help="导出 JSON")
    args = ap.parse_args()

    if args.runs:
        dll3 = BIN / (args.dll or CANDIDATES[0])
        runs = scan_runs(dll3)
        want = args.iface or []
        keys = want if want else sorted(runs)
        print(f"扫描 {dll3.name}：{len(runs)} 个接口\n")
        for k in keys:
            if k not in runs:
                print(f"### {k}: 未找到\n")
                continue
            print("=" * 74)
            print(f"接口 {k}  ({len(runs[k])} 个名)")
            print("=" * 74)
            for n in runs[k]:
                print("   ", n)
            print()
        if args.json:
            Path(args.json).write_text(
                json.dumps(runs, indent=2, ensure_ascii=False), encoding="utf-8"
            )
            print(f"已写出 {args.json}")
        return

    if args.names:
        dll2 = BIN / (args.dll or CANDIDATES[0])
        blob = dll2.read_bytes()
        strs = load_strings(blob, minlen=4)
        rx = re.compile(args.names, re.IGNORECASE)
        seen, hits2 = set(), []
        for s in strs:
            if ident_like(s) and rx.search(s) and s not in seen:
                seen.add(s)
                hits2.append(s)
        print(f"匹配 '{args.names}' 的标识符 {len(hits2)} 个（已去重）：")
        for s in sorted(hits2):
            print("   ", s)
        return

    dll_name = args.dll or CANDIDATES[0]
    dll = BIN / dll_name
    if not dll.exists():
        print(f"[FAIL] 找不到 {dll}")
        sys.exit(2)

    print(f"扫描: {dll}  ({dll.stat().st_size/1024/1024:.1f} MB)")
    data, hits = scan(dll)
    print(f"发现 {len(hits)} 个 Lua_I*.cpp 接口锚点\n")

    if args.list_interfaces or (not args.iface and not args.find and not args.all):
        for k in sorted(hits):
            print(f"  {k:<34} 窗口内候选名 {len(hits[k]):>4} 个")
        if not args.all and not args.iface:
            print("\n（用 --iface <名> 打印具体候选；--all 导出全部）")
        return

    if args.iface:
        for k in args.iface:
            print("=" * 74)
            print(f"接口 {k}")
            print("=" * 74)
            if k not in hits:
                print("  (未找到该锚点)")
                continue
            for n in hits[k]:
                print("   ", n)
            print()

    if args.find:
        print("=" * 74)
        print("全局字符串搜索")
        print("=" * 74)
        for d in CANDIDATES:
            p = BIN / d
            if not p.exists():
                continue
            blob = p.read_bytes()
            for needle in args.find:
                n = blob.count(needle.encode("ascii"))
                mark = "命中" if n else "**未命中**"
                print(f"  {d:<44} {needle:<26} {mark} ({n})")
        print()

    if args.all or args.json:
        if args.json:
            Path(args.json).write_text(
                json.dumps(hits, indent=2, ensure_ascii=False), encoding="utf-8"
            )
            print(f"已写出 {args.json}")
        if args.all:
            for k in sorted(hits):
                print("=" * 74)
                print(f"接口 {k}")
                print("=" * 74)
                for n in hits[k]:
                    print("   ", n)


if __name__ == "__main__":
    main()
