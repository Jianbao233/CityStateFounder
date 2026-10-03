# -*- coding: utf-8 -*-
"""Lua API 注册表 —— 从反编译正文里抽出所有 hks_pushnamedcclosure 注册。

背景：
  `objects/B3深度分析/lua_registrar_calls.json`（5365 条）只给了
  `{at, kind, target}`，**没有函数名**。
  但反编译正文里名字是全的，形如：
      hks_pushnamedcclosure(param_1,FUN_1805f82d0,0,"lInitializePlayer",0);
                    注册表对象 ↑        C 实现 ↑         Lua 名 ↑

本工具扫全部反编译正文，建三张表：
    name -> {lua_name, c_func, registrar}
    c_func -> [lua_name, ...]
    registrar -> [lua_name, ...]

用法：
    python lua_api_index.py --build                 # 建索引（约 1 分钟）
    python lua_api_index.py --find Color            # 按名字关键字搜
    python lua_api_index.py --impl 1805f82d0        # 按 C 实现地址反查
    python lua_api_index.py --stats
"""
import argparse
import glob
import io
import json
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

BATCH_DIR = os.path.join(
    r"D:\A-Developing\main\civ6\CIV6_AI_KnowledgeBase",
    "archive", "DLL完全解析任务", "DLL完全解析任务", "analysis_output")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_lua_api_index.json")

# hks_pushnamedcclosure(<regobj>, <cfunc>, <nup>, "<name>", <flags>)
RE = re.compile(
    r'hks_pushnamedcclosure\s*\(\s*[^,]+,\s*(?:\(code\s*\*\))?\s*(FUN_[0-9a-fA-F]+|[0-9a-fA-Fx]+)\s*,'
    r'\s*[^,]+,\s*"([^"]+)"')


def build() -> dict:
    idx = {"apis": {}, "files": 0}
    for f in glob.glob(os.path.join(BATCH_DIR, "*.json")):
        try:
            j = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(j, dict):
            continue
        for addr, rec in j.items():
            if not isinstance(rec, dict):
                continue
            body = rec.get("decompiled_code") or ""
            if "hks_pushnamedcclosure" not in body:
                continue
            for m in RE.finditer(body):
                cfunc = m.group(1)
                name = m.group(2)
                if name.startswith("l") and len(name) > 1 and name[1].isupper():
                    name = name[1:]          # lInitializePlayer -> InitializePlayer
                idx["apis"][name] = {
                    "lua_name": m.group(2),
                    "c_func": cfunc,
                    "registrar": rec.get("name") or addr,
                }
    idx["files"] = len(idx["apis"])
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(idx, fh, ensure_ascii=False)
    return idx


def load() -> dict:
    if os.path.exists(OUT):
        return json.load(open(OUT, encoding="utf-8"))
    return build()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--find", help="按名字关键字搜（不区分大小写）")
    ap.add_argument("--impl", help="按 C 实现地址反查")
    ap.add_argument("--stats", action="store_true")
    a = ap.parse_args()

    idx = build() if a.build else load()
    apis = idx.get("apis", {})
    print(f"  Lua API 总数: {len(apis)}\n")

    if a.stats:
        return 0

    if a.find:
        key = a.find.lower()
        hits = [(k, v) for k, v in sorted(apis.items()) if key in k.lower()]
        print(f"  含 '{a.find}' 的 API: {len(hits)} 个")
        for k, v in hits[:60]:
            print(f"    {k:36} C实现={v['c_func']:14} 注册者={v['registrar']}")
        return 0

    if a.impl:
        key = a.impl.lower().lstrip("0x")
        hits = [(k, v) for k, v in sorted(apis.items())
                if v["c_func"].lower().lstrip("0x").endswith(key)]
        print(f"  实现 {a.impl} 对应的 Lua API: {len(hits)} 个")
        for k, v in hits:
            print(f"    {k:36} 注册者={v['registrar']}")
        return 0

    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
