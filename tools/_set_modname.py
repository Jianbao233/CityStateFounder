# -*- coding: utf-8 -*-
"""把本地化文件里的 mod 名称改成带版本号的形式。

⚠️ 格式陷阱：这个文件用
      <Replace Tag="..." Language="..."><Text>值</Text></Replace>
   —— 值在【子元素 Text】里，不在 Replace 的文本节点里。
   直接对 Replace 标签之间做正则替换只会动到空白，值原封不动。
"""
import re, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

PAIRS = [
    ("LOC_CSF_MOD_NAME", "zh_Hans_CN", "城邦缔造者 v1.0.2"),
    ("LOC_CSF_MOD_NAME", "en_US", "City-State Founder v1.0.2"),
]

for tag, lang, value in PAIRS:
    pat = (r'(<Replace Tag="' + tag + r'" Language="' + lang + r'">\s*<Text>)'
           r'[^<]*'
           r'(</Text>)')
    new, n = re.subn(pat, lambda m: m.group(1) + value + m.group(2), src)
    if n == 0:
        print(f"  ⚠️ 没匹配到 {tag} / {lang}")
    else:
        src = new
        print(f"  ✅ {tag} [{lang}] -> {value}  （{n} 处）")

open(path, "w", encoding="utf-8", newline="\n").write(src)
