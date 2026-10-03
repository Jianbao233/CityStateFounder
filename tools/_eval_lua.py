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
# cs_probe 会先打印一长串 Lua 状态列表，只保留响应主体
lines = out.splitlines()
keep = []
started = False
for l in lines:
    if "[响应]" in l:
        started = True
    if started:
        keep.append(l)
if not keep:
    # 没拿到响应 → 原样打印尾部，便于看错误
    keep = lines[-40:]
for l in keep:
    print(l)
