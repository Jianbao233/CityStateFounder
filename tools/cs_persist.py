#!/usr/bin/env python3
"""U4 持久化测试：杀进程 → 重启 → 读档 → 状态对比。

用途：验证「运行时用 Players[id]:GetCities():Create(x,y) 建出的城邦城市，
      存档 → 完全重启游戏 → 读档 之后是否还在」。

依据（游戏本体源码）：
  存档  Base\\Assets\\UI\\Menus\\InGameTopOptionsMenu.lua:183-195
  读档  Base\\Assets\\UI\\Automation\\Automation_DailySmokeTest.lua:258-279
        Base\\Assets\\UI\\FrontEnd\\LoadGameMenu.lua:108

用法：
  python cs_persist.py --save-name CSTEST_01
  python cs_persist.py --save-name CSTEST_01 --no-kill   # 游戏已在主菜单
"""

from __future__ import annotations

import argparse
import asyncio
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


def log(m: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)


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


async def connect():
    """连接 FireTuner（带重试）。

    注意：不要设 SO_LINGER(1,0) 强制 RST——实测会让游戏侧 tuner 进入异常，
    后续连接报 WinError 64（"指定的网络名不再可用"）。用优雅关闭即可。
    """
    last = None
    for _ in range(6):
        try:
            return await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 6.0)
        except Exception as ex:
            last = ex
            await asyncio.sleep(2.0)
    raise last if last else RuntimeError("connect failed")


async def close_conn(writer) -> None:
    """优雅关闭连接。"""
    try:
        writer.close()
        await asyncio.wait_for(writer.wait_closed(), 3.0)
    except Exception:
        pass


async def lsq(reader, writer):
    await send(writer, TAG_HANDSHAKE, "LSQ:")
    m = await recv(reader, 8.0)
    return PB.parse_states(m[1]) if m else []


async def run_lua(reader, writer, idx, code, timeout=60.0):
    await send(writer, TAG_COMMAND, f"CMD:{idx}:{code}")
    m = await recv(reader, timeout)
    resp = m[1] if m else None
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
    r = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {GAME_PROC}*", "/NH"],
        capture_output=True, text=True,
    )
    return GAME_PROC in (r.stdout or "")


LOAD_LUA = """
local loadGame = {{}};
loadGame.Location = SaveLocations.LOCAL_STORAGE;
loadGame.Type = SaveTypes.SINGLE_PLAYER;
loadGame.IsAutosave = false;
loadGame.IsQuicksave = false;
loadGame.Directory = SaveDirectories.DEFAULT;
loadGame.Name = "{name}";
print("LOADGAME_CALL name=" .. tostring(loadGame.Name));
local ok, res = pcall(function() return Network.LoadGame(loadGame, ServerType.SERVER_TYPE_NONE) end);
print("LOADGAME_RESULT ok=" .. tostring(ok) .. " res=" .. tostring(res));
"""


async def wait_states(want, timeout, need_stable=1, skip_states=None):
    deadline = time.time() + timeout
    stable = 0
    while time.time() < deadline:
        try:
            reader, writer = await connect()
            states = await lsq(reader, writer)
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


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--save-name", default="CSTEST_01")
    ap.add_argument("--no-kill", action="store_true")
    args = ap.parse_args()

    # ---- 1. 杀掉游戏（必须完全重启进程，才算真持久化测试）--------------
    if not args.no_kill:
        if game_running():
            log("杀掉游戏进程（完全重启才算真持久化测试）")
            subprocess.run(["taskkill", "/IM", f"{GAME_PROC}.exe", "/F"], capture_output=True)
            subprocess.run(["taskkill", "/IM", f"{GAME_PROC}_DX12.exe", "/F"], capture_output=True)
            await asyncio.sleep(12)

        log("重新拉起游戏")
        subprocess.run(["cmd", "/c", "start", "", "steam://run/289070"], check=False)

    log("等待 4318（最多 300s；本机首次启动常崩 amdxc64.dll）...")
    t0 = time.time()
    while time.time() - t0 < 300:
        if port_open():
            log("4318 已监听")
            break
        await asyncio.sleep(3)
    else:
        log("[FAIL] 4318 始终未监听")
        return

    # ---- 2. 等主菜单 → 读档 ---------------------------------------------
    log("等待 MainMenu 就绪（要求连续 2 次可见）...")
    reader, writer, states, mm = await wait_states("MainMenu", 300, need_stable=2)
    if mm is None:
        log("[FAIL] 未等到 MainMenu")
        return

    lua = LOAD_LUA.format(name=args.save_name)
    log(f"在 state {mm} (MainMenu) 调用 Network.LoadGame('{args.save_name}')")
    resp, extra = await run_lua(reader, writer, mm, lua, timeout=30.0)
    if resp:
        print(f"[响应] {resp}")
    for x in extra:
        print(x)
    await close_conn(writer)
    await asyncio.sleep(6)

    # ---- 3. 等 GameCore → 跑快照 ---------------------------------------
    log("等待 GameCore_Tuner 稳定（要求连续 3 次可见）...")
    reader, writer, states, gc = await wait_states("GameCore_Tuner", 420, need_stable=3)
    if gc is None:
        log("[FAIL] 读档后 GameCore_Tuner 未出现")
        return
    log(f"GameCore_Tuner 就绪于 state {gc}")

    print("\n" + "#" * 76)
    print("########## 读档后快照 ##########")
    print("#" * 76)
    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["snapshot"], timeout=90.0)
    if resp:
        print(f"[响应] {resp}")
    for x in extra:
        print(x)

    await close_conn(writer)
    log("U4 测试完成")


if __name__ == "__main__":
    asyncio.run(main())
