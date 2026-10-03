#!/usr/bin/env python3
"""U2/U5/U6/U7 综合验证编排。

策略：不依赖"禁用 mod"。报错洪水只在【自动播放期间】（单位移动触发
CCB2_MovementMarkers 的 OnUnitMoved）出现，**播放结束后自然停止**，
届时 tuner 恢复可用。

流程：
  1. 拉起游戏（带重试；本机约 50% 概率崩在 amdxc64.dll）
  2. 读档 CSTEST_01
  3. u567_setup   —— 布置四项测试条件
  4. AutoplayManager 跑 N 回合
  5. 轮询 Lua.log 大小，连续 M 次不增长 → 判定洪水已停（= 播放结束）
  6. u567_verify  —— 复查四项结果

用法：
  python cs_u567.py --turns 30
  python cs_u567.py --turns 30 --no-launch
"""

from __future__ import annotations

import argparse
import asyncio
import os
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import cs_probe as PB  # noqa: E402

HOST, PORT = "127.0.0.1", 4318
HEADER_FMT = "<Ii"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
TAG_HANDSHAKE, TAG_COMMAND = 4, 3
GAME_PROC = "CivilizationVI"
LUA_LOG = Path(os.environ.get("LOCALAPPDATA", "")) / "Firaxis Games" / "Sid Meier's Civilization VI" / "Logs" / "Lua.log"
OUT = HERE / "cs_u567_out.txt"

_lines: list[str] = []


def log(m: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {m}"
    print(line, flush=True)
    _lines.append(line)
    try:                       # 立即落盘，便于外部监控进度
        OUT.write_text("\n".join(_lines), encoding="utf-8")
    except Exception:
        pass


def save() -> None:
    OUT.write_text("\n".join(_lines), encoding="utf-8")


def lua_log_size() -> int:
    try:
        return LUA_LOG.stat().st_size
    except Exception:
        return 0


# --------------------------------------------------------------------------
async def send(writer, tag, payload):
    data = payload.encode("utf-8") + b"\x00"
    writer.write(struct.pack(HEADER_FMT, len(data), tag) + data)
    await writer.drain()


async def recv(reader, timeout):
    try:
        header = await asyncio.wait_for(reader.readexactly(HEADER_SIZE), timeout)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, ConnectionError):
        return None
    length, tag = struct.unpack(HEADER_FMT, header)
    try:
        data = await asyncio.wait_for(reader.readexactly(length), timeout)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, ConnectionError):
        return None
    return tag, data.rstrip(b"\x00").decode("utf-8", errors="replace")


async def drain(reader, timeout=0.8):
    out = []
    while True:
        m = await recv(reader, timeout)
        if m is None:
            break
        out.append(m[1])
    return out


async def connect():
    last = None
    for _ in range(5):
        try:
            return await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 6.0)
        except Exception as ex:
            last = ex
            await asyncio.sleep(2.0)
    raise last if last else RuntimeError("connect failed")


async def close_conn(writer):
    try:
        writer.close()
        await asyncio.wait_for(writer.wait_closed(), 3.0)
    except Exception:
        pass


async def handshake(reader, writer):
    await drain(reader, 2.0)
    await send(writer, TAG_HANDSHAKE, "APP:")
    app = "<无响应>"
    for _ in range(5):
        m = await recv(reader, 3.0)
        if m is None:
            break
        app = m[1]
        if "Civ6" in m[1] or "Civilization" in m[1]:
            break
    for _ in range(10):
        await send(writer, TAG_HANDSHAKE, "LSQ:")
        for _ in range(5):
            m = await recv(reader, 3.0)
            if m is None:
                break
            cand = PB.parse_states(m[1])
            if any(n == "Main State" for _, n in cand):
                return app, cand
        await drain(reader, 0.8)
    return app, []


async def run_lua(reader, writer, idx, code, timeout=60.0):
    await send(writer, TAG_COMMAND, f"CMD:{idx}:{code}")
    resp = None
    for _ in range(10):
        m = await recv(reader, timeout)
        if m is None:
            break
        resp = m[1]
        if m[1] and not m[1].startswith("Runtime Error"):
            break
    extra = await drain(reader, 1.0)
    return resp, extra


def find(states, pat):
    for i, n in states:
        if pat.lower() == n.lower():
            return i
    for i, n in states:
        if pat.lower() in n.lower():
            return i
    return None


def port_open() -> bool:
    import socket

    with socket.socket() as s:
        s.settimeout(1.0)
        return s.connect_ex((HOST, PORT)) == 0


def game_running() -> bool:
    r = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {GAME_PROC}*", "/NH"],
                       capture_output=True, text=True)
    return GAME_PROC in (r.stdout or "")


def kill_crash_reporter() -> bool:
    """杀掉 Firaxis 崩溃报告器。

    ⭐ 实测关键规律：本机游戏启动**几乎必然先崩一次**（amdxc64.dll），
    然后弹出「Firaxis崩溃报告」模态框。**该模态框不关掉，后续启动尝试全部无效**
    （表现为"无进程、无崩溃日志"）。杀掉它再重试，第二次通常成功。
    """
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq FiraxisBugReporter*", "/NH"],
                       capture_output=True, text=True)
    if "FiraxisBugReporter" in (r.stdout or ""):
        subprocess.run(["taskkill", "/IM", "FiraxisBugReporter.exe", "/F"], capture_output=True)
        return True
    return False


LOAD_LUA = """
local lg = {}
lg.Location = SaveLocations.LOCAL_STORAGE
lg.Type = SaveTypes.SINGLE_PLAYER
lg.IsAutosave = false
lg.IsQuicksave = false
lg.Directory = SaveDirectories.DEFAULT
lg.Name = "{name}"
local ok, res = pcall(function() return Network.LoadGame(lg, ServerType.SERVER_TYPE_NONE) end)
print("LOADGAME ok=" .. tostring(ok) .. " res=" .. tostring(res))
"""


async def wait_states(want, timeout, need_stable=1):
    deadline = time.time() + timeout
    stable = 0
    while time.time() < deadline:
        try:
            reader, writer = await connect()
            states = await handshake(reader, writer)
            idx = find(states, want)
            log(f"  状态数={len(states)} {want}={idx}")
            if idx is not None:
                stable += 1
                if stable >= need_stable:
                    return reader, writer, states, idx
            else:
                stable = 0
            await close_conn(writer)
        except Exception as ex:
            log(f"  连接失败: {ex}")
            stable = 0
        await asyncio.sleep(10)
    return None, None, None, None


def emit(title, resp, extra):
    log("=" * 70)
    log(f"## {title}")
    log("=" * 70)
    if resp:
        _lines.append(resp)
        print(resp, flush=True)
    for x in extra:
        if "Runtime Error" in x or "CCB2_MovementMarkers" in x or "stack traceback" in x:
            continue
        _lines.append(x)
        print(x, flush=True)
    save()


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", default="CSTEST_01")
    ap.add_argument("--turns", type=int, default=30)
    ap.add_argument("--no-launch", action="store_true")
    ap.add_argument("--settle", type=int, default=5, help="连续多少次日志不增长判定洪水已停")
    args = ap.parse_args()

    # ---- 1. 启动 --------------------------------------------------------
    if not args.no_launch:
        up = False
        for attempt in range(1, 6):
            log(f"启动尝试 {attempt}")
            if game_running():
                subprocess.run(["taskkill", "/IM", f"{GAME_PROC}.exe", "/F"], capture_output=True)
                subprocess.run(["taskkill", "/IM", f"{GAME_PROC}_DX12.exe", "/F"], capture_output=True)
                await asyncio.sleep(12)
            subprocess.run(["cmd", "/c", "start", "", "steam://run/289070"], check=False)
            for i in range(24):
                await asyncio.sleep(10)
                if kill_crash_reporter():
                    log("  [crash-reporter] 已杀掉崩溃报告器")
                if not port_open():
                    continue
                try:
                    r, w = await connect()
                    _, st = await handshake(r, w)
                    await close_conn(w)
                    if any(n == "Main State" for _, n in st):
                        log(f"  [{i*10}s] tuner 可用")
                        up = True
                        break
                except Exception:
                    pass
            if up:
                break
        if not up:
            log("[FAIL] 5 次启动均失败")
            save()
            return

    # ---- 2. 读档 --------------------------------------------------------
    log("等待 MainMenu...")
    reader, writer, states, mm = await wait_states("MainMenu", 300, need_stable=2)
    if mm is None:
        log("[FAIL] 未等到 MainMenu")
        save()
        return
    resp, extra = await run_lua(reader, writer, mm, LOAD_LUA.format(name=args.save), 30.0)
    emit("读档", resp, extra)
    await close_conn(writer)
    await asyncio.sleep(6)

    log("等待 GameCore_Tuner...")
    reader, writer, states, gc = await wait_states("GameCore_Tuner", 420, need_stable=3)
    if gc is None:
        log("[FAIL] GameCore_Tuner 未出现")
        save()
        return
    ap_idx = find(states, "ActionPanel")
    log(f"GameCore_Tuner={gc}  ActionPanel={ap_idx}")

    # ---- 3. 布置 --------------------------------------------------------
    log("运行 u567_setup（布置四项测试条件）...")
    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["u567_setup"], 180.0)
    emit("步骤 3：布置（u567_setup）", resp, extra)

    # ---- 4. 自动播放 ----------------------------------------------------
    log(f"启动自动播放 {args.turns} 回合...")
    auto = (f"AutoplayManager.SetTurns({args.turns}) "
            "AutoplayManager.SetActive(true) print('AUTOPLAY_STARTED')")
    resp, extra = await run_lua(reader, writer, ap_idx if ap_idx else gc, auto, 30.0)
    emit("步骤 4：启动自动播放", resp, extra)

    # ---- 5. 等洪水停（= 播放结束）--------------------------------------
    log("轮询 Lua.log 增长，等报错洪水停止（= 自动播放结束）...")
    last = lua_log_size()
    quiet = 0
    deadline = time.time() + 60 * 30
    while time.time() < deadline:
        await asyncio.sleep(20)
        cur = lua_log_size()
        delta = cur - last
        log(f"  Lua.log {cur/1024/1024:.1f} MB  增长 {delta/1024:.0f} KB")
        last = cur
        if delta < 20 * 1024:          # 20 秒增长 < 20KB 视为静默
            quiet += 1
            if quiet >= args.settle:
                log("洪水已停（判定自动播放结束）")
                break
        else:
            quiet = 0
    else:
        log("[WARN] 等满 30 分钟仍未静默，仍尝试复查")

    await asyncio.sleep(20)

    # ---- 6. 复查 --------------------------------------------------------
    log("运行 u567_verify（复查四项结果）...")
    try:
        reader, writer = await connect()
        states = await handshake(reader, writer)
        gc = find(states, "GameCore_Tuner")
        log(f"  重连后 GameCore_Tuner={gc}")
    except Exception as ex:
        log(f"  重连失败: {ex}")
        save()
        return

    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["u567_verify"], 240.0)
    emit("步骤 6：复查（u567_verify）", resp, extra)

    await close_conn(writer)
    log("完成")
    save()


if __name__ == "__main__":
    asyncio.run(main())
