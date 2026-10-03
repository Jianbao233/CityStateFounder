# -*- coding: utf-8 -*-
"""Lua 块配平检查（v3）—— Civ6 是 Lua 5.1，块不配平会让【整份脚本不加载】，
所以每次改完 Lua 都要跑一次。

两个容易踩的假警报：
  ① 块注释 --[[ ... ]] 里的 if/for/do 会被算进去 → 必须先剥掉
  ② `for ... do` / `while ... do` 同一行有 2 个开关键字但只有 1 个 end
     → 要把"for/while 自带的那一个 do"减掉，否则每行虚增 1
"""
import re, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def strip_lua(src):
    """去掉块注释、行注释、字符串字面量。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        m = re.match(r"--\[(=*)\[", src[i:])
        if m:                                    # 块注释
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + len(m.group(0)))
            i = n if j < 0 else j + len(close)
            continue
        if src.startswith("--", i):              # 行注释
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        ch = src[i]
        if ch in "\"'":                          # 字符串
            j = i + 1
            while j < n and src[j] != ch:
                if src[j] == "\\":
                    j += 1
                j += 1
            i = j + 1
            out.append('""')
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def count_line(ln):
    n_for = len(re.findall(r"\b(for|while)\b", ln))
    n_do = len(re.findall(r"\bdo\b", ln))
    n_if = len(re.findall(r"\bif\b", ln))
    n_fn = len(re.findall(r"\bfunction\b", ln))
    n_end = len(re.findall(r"\bend\b", ln))
    # for/while 自带的那一个 do 不算额外的块
    return n_if + n_fn + n_for + max(0, n_do - n_for), n_end


for path in sys.argv[1:]:
    raw = open(path, encoding="utf-8").read()
    src = strip_lua(raw)
    name = path.split("\\")[-1]
    paren = all(src.count(o) == src.count(c)
                for o, c in (("(", ")"), ("{", "}"), ("[", "]")))
    depth = 0
    opens = 0
    first_neg = None
    for i, ln in enumerate(src.splitlines(), 1):
        o, e = count_line(ln)
        opens += o
        depth += o - e
        if depth < 0 and first_neg is None:
            first_neg = (i, ln.strip()[:60], depth)
    goto = [l.strip() for l in raw.splitlines() if l.strip().startswith("goto")]
    flag = "✅ 配平" if depth == 0 else "⚠️ 不配平"
    print(f"  {name}")
    print(f"    括号={'OK' if paren else '⚠️'}  块开启={opens}  "
          f"最终深度={depth}  {flag}")
    if first_neg:
        print(f"    首次变负 : {first_neg}")
    if goto:
        print(f"    ⚠️ goto（Lua 5.1 不支持）: {goto}")
