# -*- coding: utf-8 -*-
"""把一个 .lua 文件的内容经 cs_probe 的传输层发到 FireTuner 执行。

为什么需要它：`cs_probe.py --eval "<lua>"` 在 PowerShell 里引号会被吃掉
（实测：命令被拆成多个参数报 "unrecognized arguments"）。
写文件再读，绕开 shell 引号。

用法：
    python _eval_lua.py <lua文件> [--state <状态名>] [--port 4318]
"""
import io, pathlib, subprocess, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(2)

lua_path = pathlib.Path(sys.argv[1])
code = lua_path.read_text(encoding="utf-8")

here = pathlib.Path(__file__).parent
probe = here / "cs_probe.py"

cmd = [sys.executable, "-u", str(probe), "--eval", code]
# 透传可选参数
rest = sys.argv[2:]
cmd += rest if rest else ["--port", "4318"]

print(f"→ 执行 {lua_path.name}（{len(code)} 字节）")
r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
out = (r.stdout or "") + (r.stderr or "")
# 只打印响应主体，跳过状态列表（很长）
lines = out.splitlines()
start = 0
for i, l in enumerate(lines):
    if "[响应]" in l:
        start = i
        break
for l in lines[start:]:
    print(l)
if r.returncode not in (0, None):
    print(f"[退出码 {r.returncode}]")
