# -*- coding: utf-8 -*-
"""把 customcs 探针块从文件末尾移到 `if __name__ == "__main__":` 之前。

为什么必须移：
  cs_probe.py 的结构是「全部 PROBES 定义 → def main() → if __name__: main()」。
  探针块若在 `if __name__` 之后，模块级赋值发生在 main() 已经跑完之后，
  `--list` / `--probe customcs` 都看不到它（实测踩到）。
"""
import io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

src = sys.argv[1] if len(sys.argv) > 1 else "cs_probe.py"
text = open(src, encoding="utf-8").read()

MARK = "# ---- 26. 自定义城邦验证"
GUARD = 'if __name__ == "__main__":'

if MARK not in text:
    print("❌ 找不到探针块标记，未修改")
    sys.exit(1)

start = text.index(MARK)
# 块尾 = 从 start 起第一个顶格的 ")" 行
tail = text.index("\n)\n", start) + 3
block = text[start:tail]
rest = text[:start] + text[tail:]

gi = rest.index(GUARD)
new = rest[:gi] + block.rstrip("\n") + "\n\n\n" + rest[gi:]

# 收掉可能出现的连续多余空行
while "\n\n\n\n" in new:
    new = new.replace("\n\n\n\n", "\n\n\n")

open(src, "w", encoding="utf-8", newline="\n").write(new)

lines = new.splitlines()
mi = next(i for i, l in enumerate(lines) if l.startswith(MARK))
gi = next(i for i, l in enumerate(lines) if l.startswith(GUARD))
print(f"✅ 探针块现在在 行 {mi+1}，__main__ 在 行 {gi+1}  → {'顺序正确' if mi < gi else '❌ 仍错'}")
print(f"   文件共 {len(lines)} 行")
