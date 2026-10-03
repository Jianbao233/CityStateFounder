#!/usr/bin/env python3
"""U2/U5/U6/U7 综合验证 —— 单连接版。

⭐ 为什么要单连接：
   实测 4318 上出现 `CloseWait` 堆积（客户端关了、游戏侧没关），攒到 5~6 个后
   tuner 就完全不再响应（`游戏标识: <无响应>` / `Lua 状态 (0)`）。
   **每次失败的连接尝试都会留下一个泄漏。** 所以本脚本全程只开**一条** TCP 连接，
   包括状态轮询（用同一条连接重复发 LSQ:）。

流程（全在一条连接上）：
  1. 连接 + 握手
  2. 在 MainMenu 状态 Network.LoadGame
  3. 同连接轮询 LSQ: 直到 GameCore_Tuner 出现
  4. u567_setup → AutoplayManager → 等 Lua.log 静默 → u567_verify

用法：
  python cs_u567_single.py --turns 20
  python cs_u567_single.py --turns 20 --launch   # 需要时自己拉游戏
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
LUA_LOG = (
    Path(os.environ.get("LOCALAPPDATA", ""))
    / "Firaxis Games" / "Sid Meier's Civilization VI" / "Logs" / "Lua.log"
)
OUT = HERE / "cs_u567_single_out.txt"

_lines: list[str] = []


def log(m: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {m}"
    print(line, flush=True)
    _lines.append(line)
    try:
        OUT.write_text("\n".join(_lines), encoding="utf-8")
    except Exception:
        pass


def lua_log_size() -> int:
    try:
        return LUA_LOG.stat().st_size
    except Exception:
        return 0


def kill_crash_reporter() -> bool:
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq FiraxisBugReporter*", "/NH"],
                       capture_output=True, text=True)
    if "FiraxisBugReporter" in (r.stdout or ""):
        subprocess.run(["taskkill", "/IM", "FiraxisBugReporter.exe", "/F"], capture_output=True)
        return True
    return False


def game_running() -> bool:
    r = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {GAME_PROC}*", "/NH"],
                       capture_output=True, text=True)
    return GAME_PROC in (r.stdout or "")


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


async def drain(reader, timeout=0.6):
    out = []
    while True:
        m = await recv(reader, timeout)
        if m is None:
            break
        out.append(m[1])
    return out


async def open_conn():
    """只连一次；失败就等，不反复重连（避免泄漏）。"""
    for _ in range(3):
        try:
            r, w = await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 6.0)
            return r, w
        except Exception as ex:
            log(f"  连接失败: {ex}")
            await asyncio.sleep(5)
    return None, None


async def lsq(reader, writer):
    await send(writer, TAG_HANDSHAKE, "LSQ:")
    for _ in range(8):
        m = await recv(reader, 5.0)
        if m is None:
            return []
        cand = PB.parse_states(m[1])
        if any(n == "Main State" for _, n in cand):
            return cand
    return []


async def run_lua(reader, writer, idx, code, timeout=120.0):
    await send(writer, TAG_COMMAND, f"CMD:{idx}:{code}")
    resp = None
    for _ in range(12):
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
    OUT.write_text("\n".join(_lines), encoding="utf-8")


LOAD_LUA = """
local lg = {{}}
lg.Location = SaveLocations.LOCAL_STORAGE
lg.Type = SaveTypes.SINGLE_PLAYER
lg.IsAutosave = false
lg.IsQuicksave = false
lg.Directory = SaveDirectories.DEFAULT
lg.Name = "{name}"
local ok, res = pcall(function() return Network.LoadGame(lg, ServerType.SERVER_TYPE_NONE) end)
print("LOADGAME ok=" .. tostring(ok) .. " res=" .. tostring(res))
"""


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", default="CSTEST_01")
    ap.add_argument("--turns", type=int, default=20)
    ap.add_argument("--launch", action="store_true")
    ap.add_argument("--settle", type=int, default=4)
    args = ap.parse_args()

    if args.launch:
        for attempt in range(1, 6):
            log(f"启动尝试 {attempt}")
            if game_running():
                subprocess.run(["taskkill", "/IM", f"{GAME_PROC}.exe", "/F"], capture_output=True)
                subprocess.run(["taskkill", "/IM", f"{GAME_PROC}_DX12.exe", "/F"], capture_output=True)
                await asyncio.sleep(12)
            subprocess.run(["cmd", "/c", "start", "", "steam://run/289070"], check=False)
            opened = False
            for i in range(24):
                await asyncio.sleep(10)
                if kill_crash_reporter():
                    log("  [crash-reporter] 已杀掉崩溃报告器")
                import socket
                with socket.socket() as s:
                    s.settimeout(1.0)
                    if s.connect_ex((HOST, PORT)) != 0:
                        continue
                log(f"  [{i*10}s] 端口已开")
                opened = True
                break
            if opened:
                break

    # ---- 唯一的一条连接 ------------------------------------------------
    log("建立唯一连接...")
    reader, writer = await open_conn()
    if reader is None:
        log("[FAIL] 连不上")
        return

    await drain(reader, 2.0)
    await send(writer, TAG_HANDSHAKE, "APP:")
    m = await recv(reader, 8.0)
    log(f"游戏标识: {m[1] if m else '<无响应>'}")
    states = await lsq(reader, writer)
    log(f"状态数: {len(states)}")
    for i, n in states:
        if n in ("MainMenu", "GameCore_Tuner", "ActionPanel", "InGame"):
            log(f"  {i}: {n}")

    if not states:
        log("[FAIL] 握手拿不到状态列表——tuner 可能被泄漏连接占住，需重启游戏")
        return

    # ---- 若在 MainMenu 则读档 ------------------------------------------
    mm = find(states, "MainMenu")
    if mm is not None:
        log(f"在 state {mm}(MainMenu) 读档 {args.save}")
        resp, extra = await run_lua(reader, writer, mm, LOAD_LUA.format(name=args.save), 40.0)
        emit("读档", resp, extra)

    # ---- 同连接轮询 GameCore_Tuner -------------------------------------
    log("同连接轮询 GameCore_Tuner（最多 8 分钟）...")
    gc, ap_idx = None, None
    deadline = time.time() + 480
    while time.time() < deadline:
        await asyncio.sleep(15)
        try:
            states = await lsq(reader, writer)
        except Exception as ex:
            log(f"  LSQ 异常: {ex}")
            break
        gc = find(states, "GameCore_Tuner")
        ap_idx = find(states, "ActionPanel")
        log(f"  状态数={len(states)} GameCore_Tuner={gc} ActionPanel={ap_idx}")
        if gc is not None:
            break
    if gc is None:
        log("[FAIL] GameCore_Tuner 未出现")
        return

    # ---- 布置 ----------------------------------------------------------
    log("u567_setup（布置四项测试条件）...")
    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["u567_setup"], 240.0)
    emit("步骤：布置（u567_setup）", resp, extra)

    # ---- 自动播放 ------------------------------------------------------
    # ⚠️ 必须四个调用齐全（依据游戏本体 Automation_DailySmokeTest.lua:194-198）：
    #    SetTurns → SetReturnAsPlayer → SetObserveAsPlayer → SetActive(true)
    #    实测漏掉 SetReturnAsPlayer 时自动播放不会停（一路跑到 turn 130）
    log(f"启动自动播放 {args.turns} 回合...")
    auto = (f"AutoplayManager.SetTurns({args.turns}) "
            "AutoplayManager.SetReturnAsPlayer(0) "
            "AutoplayManager.SetObserveAsPlayer(0) "
            "AutoplayManager.SetActive(true) print('AUTOPLAY_STARTED')")
    resp, extra = await run_lua(reader, writer, ap_idx if ap_idx else gc, auto, 40.0)
    emit("步骤：启动自动播放", resp, extra)

    # ---- 等洪水静默（= 播放结束）---------------------------------------
    log("等 Lua.log 静默（= 自动播放结束 / 洪水停止）...")
    last, quiet = lua_log_size(), 0
    deadline = time.time() + 60 * 25
    while time.time() < deadline:
        await asyncio.sleep(20)
        cur = lua_log_size()
        delta = cur - last
        log(f"  Lua.log {cur/1024/1024:.1f} MB  增长 {delta/1024:.0f} KB")
        last = cur
        quiet = quiet + 1 if delta < 20 * 1024 else 0
        if quiet >= args.settle:
            log("已静默，判定播放结束")
            break

    await asyncio.sleep(20)

    # ---- 复查（同连接）-------------------------------------------------
    log("u567_verify（复查四项结果）...")
    try:
        states = await lsq(reader, writer)
        gc = find(states, "GameCore_Tuner")
        log(f"  重取 GameCore_Tuner={gc}")
    except Exception as ex:
        log(f"  LSQ 失败: {ex}")
        return
    if gc is None:
        log("[FAIL] 复查时 GameCore_Tuner 不见了")
        return

    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["u567_verify"], 300.0)
    emit("步骤：复查（u567_verify）", resp, extra)

    log("完成")
    try:
        writer.close()
        await asyncio.wait_for(writer.wait_closed(), 3.0)
    except Exception:
        pass


if __name__ == "__main__":
    import traceback

    try:
        asyncio.run(main())
    except BaseException:
        # ★ 异常必须落盘：此前脚本在隐藏窗口里静默退出，traceback 全丢了，
        #   导致"脚本卡住"无法诊断。
        tb = traceback.format_exc()
        _lines.append("!!! 异常退出 !!!")
        _lines.append(tb)
        try:
            OUT.write_text("\n".join(_lines), encoding="utf-8")
        except Exception:
            pass
        print(tb, flush=True)
        raise
