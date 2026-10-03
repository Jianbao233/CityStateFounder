#!/usr/bin/env python3
"""U2 测试：休眠城邦能否稳定存活。

流程：
  1. 拉起游戏 → 读档 CSTEST_01（turn 1，城邦持有移民但尚未建城）
  2. 把其中一个城邦「送下地图」（InitUnit(-1,-1) + 杀掉地图上单位）→ 成为休眠城邦
  3. 用 AutoplayManager 跑 N 回合
  4. 复查：休眠城邦是否存活？是否保持 0 城？其余城邦是否正常建城？

依据：
  机制   Free City States [Revived] 的 DeleteUnitsOnMap()
  自动播放  Base\\Assets\\UI\\ActionPanel.lua:1112 "kicked off from the Tuner."
  读档   Base\\Assets\\UI\\Automation\\Automation_DailySmokeTest.lua:258-279

用法：
  python cs_u2.py --save CSTEST_01 --turns 40
  python cs_u2.py --save CSTEST_01 --turns 40 --no-launch   # 游戏已在主菜单
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


async def drain(reader, timeout=0.8):
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
    for _ in range(12):
        await send(writer, TAG_HANDSHAKE, "LSQ:")
        for _ in range(6):
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


LOAD_LUA = """
local loadGame = {{}};
loadGame.Location = SaveLocations.LOCAL_STORAGE;
loadGame.Type = SaveTypes.SINGLE_PLAYER;
loadGame.IsAutosave = false;
loadGame.IsQuicksave = false;
loadGame.Directory = SaveDirectories.DEFAULT;
loadGame.Name = "{name}";
local ok, res = pcall(function() return Network.LoadGame(loadGame, ServerType.SERVER_TYPE_NONE) end);
print("LOADGAME ok=" .. tostring(ok) .. " res=" .. tostring(res));
"""

TURN_LUA = """
local t = -1;
pcall(function() t = Game.GetCurrentGameTurn() end);
print("TURN=" .. tostring(t));
"""


async def get_turn(reader, writer, gc_idx):
    """读当前回合（用 CMD 直接跑，避免探针噪声）。"""
    await send(writer, TAG_COMMAND, f'CMD:{gc_idx}:local t=-1 pcall(function() t=Game.GetCurrentGameTurn() end) print("TURNNOW="..tostring(t))')
    best = None
    for _ in range(8):
        m = await recv(reader, 20.0)
        if m is None:
            break
        if "TURNNOW=" in m[1]:
            try:
                best = int(m[1].split("TURNNOW=")[1].strip().split()[0])
            except Exception:
                pass
            break
    return best


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
    print("\n" + "=" * 74)
    print(f"## {title}")
    print("=" * 74)
    if resp:
        print(resp)
    for x in extra:
        if "Runtime Error" in x or "CCB2_MovementMarkers" in x:
            continue
        print(x)


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", default="CSTEST_01")
    ap.add_argument("--turns", type=int, default=40)
    ap.add_argument("--no-launch", action="store_true")
    args = ap.parse_args()

    # ---- 1. 启动 + 读档 ------------------------------------------------
    if not args.no_launch:
        if game_running():
            log("杀掉旧进程")
            subprocess.run(["taskkill", "/IM", f"{GAME_PROC}.exe", "/F"], capture_output=True)
            subprocess.run(["taskkill", "/IM", f"{GAME_PROC}_DX12.exe", "/F"], capture_output=True)
            await asyncio.sleep(12)
        log("拉起游戏")
        subprocess.run(["cmd", "/c", "start", "", "steam://run/289070"], check=False)

    log("等待 4318（最多 300s）...")
    t0 = time.time()
    while time.time() - t0 < 300:
        if port_open():
            log("4318 已监听")
            break
        await asyncio.sleep(3)
    else:
        log("[FAIL] 4318 未监听")
        return

    log("等待 MainMenu...")
    reader, writer, states, mm = await wait_states("MainMenu", 300, need_stable=2)
    if mm is None:
        log("[FAIL] 未等到 MainMenu")
        return
    resp, extra = await run_lua(reader, writer, mm, LOAD_LUA.format(name=args.save), 30.0)
    emit("读档", resp, extra)
    await close_conn(writer)
    await asyncio.sleep(6)

    log("等待 GameCore_Tuner...")
    reader, writer, states, gc = await wait_states("GameCore_Tuner", 420, need_stable=3)
    if gc is None:
        log("[FAIL] GameCore_Tuner 未出现")
        return
    log(f"GameCore_Tuner = state {gc}")

    # ---- 2. 基线 -------------------------------------------------------
    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["dormant"], 90.0)
    emit("步骤 2：制造休眠城邦（基线 + 执行）", resp, extra)

    # ---- 3. 自动播放 ---------------------------------------------------
    log(f"启动自动播放 {args.turns} 回合...")
    auto_lua = (
        f"AutoplayManager.SetTurns({args.turns}) "
        "AutoplayManager.SetActive(true) print('AUTOPLAY_STARTED')"
    )
    resp, extra = await run_lua(reader, writer, find(states, "ActionPanel") or gc, auto_lua, 30.0)
    emit("步骤 3：启动自动播放", resp, extra)

    # ---- 4. 轮询回合直到稳定 -------------------------------------------
    log("轮询回合进度...")
    last, same, deadline = None, 0, time.time() + 60 * 25
    while time.time() < deadline:
        await asyncio.sleep(20)
        try:
            t = await get_turn(reader, writer, gc)
        except Exception as ex:
            log(f"  读取回合失败: {ex}")
            try:
                reader, writer = await connect()
                states = await handshake(reader, writer)
                gc = find(states, "GameCore_Tuner")
            except Exception:
                pass
            continue
        log(f"  回合 = {t}")
        if t is not None and t == last:
            same += 1
            if same >= 4:          # 连续 4 次（80 秒）不变 → 认为跑完
                log("回合已稳定，自动播放结束")
                break
        else:
            same = 0
        last = t

    # ---- 5. 复查 -------------------------------------------------------
    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["snapshot"], 120.0)
    emit(f"步骤 5：跑完 {args.turns} 回合后的快照", resp, extra)

    resp, extra = await run_lua(reader, writer, gc, PB.PROBES["nativeness"], 120.0)
    emit("步骤 6：城邦原生性复查", resp, extra)

    await close_conn(writer)
    log("U2 测试完成")


if __name__ == "__main__":
    asyncio.run(main())
