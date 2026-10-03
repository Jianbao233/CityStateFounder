#!/usr/bin/env python3
"""全自动编排：拉起 Civ6 → 等主菜单 → 触发单机开局 → 等 GameCore_Tuner 稳定 → 跑探针 → 落盘。

存在的理由：这台机器上 FireTuner 状态抖动剧烈（开局过渡期状态列表 34→2 反复、
tuner 服务偶发直接关闭端口），手工一步步试代价太高。本脚本把整条链路做成一键，
每步都有重试，结果写文件，供离线分析。

用法：
  python _tmp_cs_auto.py                 # 全流程
  python _tmp_cs_auto.py --probes globals api discover world cityobj
  python _tmp_cs_auto.py --no-launch     # 游戏已在跑
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

import cs_probe as PB  # noqa: E402  （复用探针定义）

HOST, PORT = "127.0.0.1", 4318
HEADER_FMT = "<Ii"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
TAG_HANDSHAKE, TAG_COMMAND = 4, 3
GAME_PROC = "CivilizationVI"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


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


async def run_lua(reader, writer, idx, code, timeout=30.0):
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
        capture_output=True,
        text=True,
    )
    return GAME_PROC in (r.stdout or "")


def launch_game() -> None:
    log("拉起游戏 steam://run/289070 ...")
    subprocess.run(["cmd", "/c", "start", "", "steam://run/289070"], check=False)


# --------------------------------------------------------------------------
async def wait_states(want: str, timeout: float, need_stable: int = 1):
    """等待某个状态出现并连续 need_stable 次可见。返回 (reader, writer, states, idx)。"""
    deadline = time.time() + timeout
    stable = 0
    last = None
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
        last = time.time()
        await asyncio.sleep(10)
    return None, None, None, None


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-launch", action="store_true")
    ap.add_argument("--probes", nargs="*",
                    default=["globals", "api", "discover", "world", "cityobj"])
    ap.add_argument("--out", default=str(HERE / "cs_auto_out.txt"))
    args = ap.parse_args()

    out_lines: list[str] = []

    def emit(s: str) -> None:
        print(s, flush=True)
        out_lines.append(s)

    # ---- 1. 确保游戏在跑 ------------------------------------------------
    if not args.no_launch:
        if game_running():
            log("游戏进程已存在，先杀掉以便从干净主菜单开始")
            subprocess.run(["taskkill", "/IM", f"{GAME_PROC}.exe", "/F"],
                           capture_output=True)
            subprocess.run(["taskkill", "/IM", f"{GAME_PROC}_DX12.exe", "/F"],
                           capture_output=True)
            await asyncio.sleep(10)
        launch_game()

    log("等待 4318 监听（最多 300s）...")
    t0 = time.time()
    while time.time() - t0 < 300:
        if port_open():
            log("4318 已监听")
            break
        await asyncio.sleep(3)
    else:
        emit("[FAIL] 4318 始终未监听——游戏未起来或崩溃")
        Path(args.out).write_text("\n".join(out_lines), encoding="utf-8")
        return

    # ---- 2. 等主菜单 ----------------------------------------------------
    log("等待 MainMenu 就绪（最多 300s，要求连续 2 次可见）...")
    reader, writer, states, mm = await wait_states("MainMenu", 300, need_stable=2)
    if mm is None:
        emit("[WARN] 未等到 MainMenu；可能已在局内，直接找 GameCore_Tuner")
        if writer:
            await close_conn(writer)
    else:
        log(f"在 state {mm} (MainMenu) 触发 OnPlayCiv6()")
        r, e = await run_lua(reader, writer, mm, 'OnPlayCiv6() print("TRIGGERED")')
        emit(f"触发开局响应: {r}")
        for x in e:
            emit(f"  {x}")
        await close_conn(writer)
        await asyncio.sleep(5)

    # ---- 3. 等 GameCore_Tuner 稳定 --------------------------------------
    log("等待 GameCore_Tuner 稳定（最多 600s，要求连续 3 次可见）...")
    reader, writer, states, gc = await wait_states("GameCore_Tuner", 600, need_stable=3)
    if gc is None:
        emit("[FAIL] GameCore_Tuner 未出现，放弃")
        Path(args.out).write_text("\n".join(out_lines), encoding="utf-8")
        return
    log(f"GameCore_Tuner 就绪于 state {gc}")

    # ---- 4. 跑探针 ------------------------------------------------------
    for name in args.probes:
        code = PB.PROBES.get(name)
        if code is None:
            emit(f"[SKIP] 未知探针 {name}")
            continue
        emit("")
        emit("#" * 76)
        emit(f"########## 探针 {name} ##########")
        emit("#" * 76)
        try:
            resp, extra = await run_lua(reader, writer, gc, code, timeout=60.0)
            if resp:
                emit(f"[响应] {resp}")
            for x in extra:
                emit(x)
        except Exception as ex:
            emit(f"[ERROR] 探针 {name} 失败: {ex}")
            # 断线则重连
            try:
                reader, writer = await connect()
                states = await lsq(reader, writer)
                gc = find(states, "GameCore_Tuner")
                emit(f"  重连后 GameCore_Tuner = {gc}")
            except Exception as ex2:
                emit(f"  重连失败: {ex2}")
                break

    await close_conn(writer)
    Path(args.out).write_text("\n".join(out_lines), encoding="utf-8")
    log(f"结果已写入 {args.out}")


if __name__ == "__main__":
    asyncio.run(main())
