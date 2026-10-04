# -*- coding: utf-8 -*-
"""反编译正文查询工具 —— 补 `query_index.py` 只能出元数据的缺口。

背景：
  `C6DLL索引\index.json` 只有「地址 → 子系统/字符串/调用关系」，**没有函数正文**。
  正文在**另一处**：`CIV6_AI_KnowledgeBase\archive\DLL完全解析任务\...\analysis_output\
  sequential_analysis_batch_*.json`（703 个文件），每个函数带完整字段：
      name / address / classification / signature / return_type_resolved /
      decompiled_code / xrefs / xref_count / callees / callers / disassembly /
      parameters / locals

用法：
    python decomp_query.py --addr 180229940
    python decomp_query.py --addr 180229940 --full          # 完整正文
    python decomp_query.py --string "Initializing player"   # 按字符串找
    python decomp_query.py --callees 180229940              # 看它调了谁（递归一层）
    python decomp_query.py --stats
"""
import argparse
import glob
import io
import json
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

BATCH_DIR = os.path.join(
    r"D:\A-Developing\main\civ6\CIV6_AI_KnowledgeBase",
    "archive", "DLL完全解析任务", "DLL完全解析任务", "analysis_output")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_decomp_cache.json")

FIELDS = ("name", "address", "classification", "signature", "return_type_resolved",
          "decompiled_code", "callees", "callers", "xref_count",
          "parameters", "locals")


def build_cache(force: bool = False) -> dict:
    """把所有 batch 里的函数合并成 {address: record}。第一次约 30 秒，之后走缓存。"""
    if not force and os.path.exists(CACHE):
        try:
            with open(CACHE, encoding="utf-8") as fh:
                return json.load(fh)
        except Exception:
            pass
    idx = {}
    files = glob.glob(os.path.join(BATCH_DIR, "*.json"))
    for f in files:
        try:
            j = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(j, dict):
            continue
        for k, v in j.items():
            if isinstance(v, dict) and "address" in v:
                idx[k] = {kk: v.get(kk) for kk in FIELDS}
    with open(CACHE, "w", encoding="utf-8") as fh:
        json.dump(idx, fh, ensure_ascii=False)
    return idx


def show(rec: dict, full: bool, label: str = "") -> None:
    tag = f"  [{label}] " if label else "  "
    print(f"{tag}{rec.get('name')}  {rec.get('address')}")
    print(f"      分类={rec.get('classification')}  xref={rec.get('xref_count')}")
    print(f"      签名: {rec.get('signature')}")
    ps = rec.get("parameters") or []
    if ps:
        print("      参数: " + ", ".join(
            f"{p.get('name')}({p.get('type')} @{p.get('storage')})" for p in ps))
    ls = rec.get("locals") or []
    if ls:
        names = [l.get("name") for l in ls if l.get("in_decompiled_code")]
        print("      局部(正文内): " + ", ".join(str(n) for n in names))
    body = rec.get("decompiled_code") or ""
    if body:
        print("      " + "-" * 60)
        lines = body.strip().splitlines()
        if not full and len(lines) > 26:
            lines = lines[:24] + ["  ... (用 --full 看完整正文，共 %d 行)" % len(lines)]
        for ln in lines:
            print("      " + ln.rstrip())
    else:
        print("      （无正文）")
    print()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--addr", help="按地址查（可逗号分隔多个）")
    ap.add_argument("--string", help="按反编译正文里的字符串找")
    ap.add_argument("--name", help="按函数名找")
    ap.add_argument("--full", action="store_true", help="输出完整正文")
    ap.add_argument("--callees", help="列出该地址调用的函数（一层）")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--rebuild", action="store_true", help="强制重建缓存")
    a = ap.parse_args()

    if not os.path.isdir(BATCH_DIR):
        print(f"❌ 找不到 batch 目录: {BATCH_DIR}")
        return 2
    idx = build_cache(a.rebuild)
    print(f"索引: {len(idx)} 个函数（来自 {BATCH_DIR}）\n")

    if a.stats:
        withbody = sum(1 for v in idx.values() if v.get("decompiled_code"))
        print(f"  有正文: {withbody} / {len(idx)}")
        return 0

    if a.addr:
        for ad in a.addr.split(","):
            ad = ad.strip().lstrip("0x").lower()
            rec = idx.get(ad)
            if rec is None:
                print(f"  ❌ {ad} 不在索引里\n")
            else:
                show(rec, a.full)
        return 0

    if a.callees:
        ad = a.callees.strip().lstrip("0x").lower()
        rec = idx.get(ad)
        if rec is None:
            print(f"  ❌ {ad} 不在索引里")
            return 1
        print(f"  {rec['name']} 调用 {len(rec.get('callees') or [])} 个函数：")
        for c in rec.get("callees") or []:
            r2 = idx.get(c.lstrip("0x").lower())
            desc = (r2.get("decompiled_code") or "").strip().splitlines()
            hint = desc[0][:70] if desc else "（无正文）"
            print(f"    {c}  {hint}")
        print()
        return 0

    if a.string or a.name:
        key = a.string or a.name
        hits = 0
        for ad, v in sorted(idx.items()):
            hay = (v.get("decompiled_code") or "") + (v.get("name") or "")
            if key.lower() in hay.lower():
                hits += 1
                if hits <= 20:
                    body = (v.get("decompiled_code") or "").strip().splitlines()
                    first = body[0][:70] if body else ""
                    print(f"  {ad}  {v.get('name'):18} {first}")
        print(f"\n  命中 {hits} 个")
        return 0

    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
