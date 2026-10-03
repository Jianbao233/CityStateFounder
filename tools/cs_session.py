#!/usr/bin/env python3
"""单连接长会话探针：FireTuner 实测「建立自选城邦」MOD 的生死线。

背景：实测发现 FireTuner(4318) 疑似「一次连接」制——客户端断开后再连，
服务端不再响应（APP: 无回复）。因此必须**全程保持同一条 TCP 连接**：
连接 → 在主菜单触发开局 → 等 GameCore 出现 → 在 GameCore 里跑全部探针。

用法：
  python _tmp_cs_session.py            # 完整流程：触发开局 + 全部探针
  python _tmp_cs_session.py --no-start # 不触发开局，直接探测当前状态
"""

from __future__ import annotations

import argparse
import asyncio
import struct
import sys
import time

HOST, PORT = "127.0.0.1", 4318
HEADER_FMT = "<Ii"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
TAG_HANDSHAKE, TAG_COMMAND = 4, 3


async def send(writer, tag, payload):
    data = payload.encode("utf-8") + b"\x00"
    writer.write(struct.pack(HEADER_FMT, len(data), tag) + data)
    await writer.drain()


async def recv(reader, timeout):
    try:
        header = await asyncio.wait_for(reader.readexactly(HEADER_SIZE), timeout)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError):
        return None
    length, tag = struct.unpack(HEADER_FMT, header)
    try:
        data = await asyncio.wait_for(reader.readexactly(length), timeout)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError):
        return None
    return tag, data.rstrip(b"\x00").decode("utf-8", errors="replace")


async def drain(reader, timeout=0.7):
    out = []
    while True:
        m = await recv(reader, timeout)
        if m is None:
            break
        out.append(m[1])
    return out


def parse_states(raw):
    parts = [s.strip() for s in raw.split("\x00") if s.strip()]
    if len(parts) <= 1 and "\n" in raw:
        parts = [s.strip() for s in raw.split("\n") if s.strip()]
    out, i = [], 0
    while i < len(parts):
        if parts[i].isdigit() and i + 1 < len(parts):
            out.append((int(parts[i]), parts[i + 1]))
            i += 2
        else:
            out.append((len(out), parts[i]))
            i += 1
    return out


async def lsq(reader, writer):
    await send(writer, TAG_HANDSHAKE, "LSQ:")
    m = await recv(reader, 8.0)
    return parse_states(m[1]) if m else []


async def run(reader, writer, idx, code, timeout=15.0):
    await send(writer, TAG_COMMAND, f"CMD:{idx}:{code}")
    m = await recv(reader, timeout)
    resp = m[1] if m else None
    extra = await drain(reader)
    return resp, extra


def emit(label, resp, extra):
    print(f"\n----- {label} -----")
    if resp:
        print(f"[响应] {resp}")
    for e in extra:
        print(e)


# --------------------------------------------------------------------------
PRELUDE = r"""
local OUT = {}
local function P(s) OUT[#OUT+1] = tostring(s) end
local function safe(f, ...) local ok, v = pcall(f, ...) if ok then return tostring(v) end return "ERR:"..tostring(v) end
local function HN(tbl, h)
  if h == nil then return "nil" end
  local r = tbl[h]
  if r == nil then return "?"..tostring(h) end
  return r.CivilizationType or r.LeaderType or r.UnitType or r.Type or tostring(h)
end
"""
EPILOGUE = r"""
print(table.concat(OUT, "\n"))
"""

PROBE_GLOBALS = PRELUDE + r"""
for _, n in ipairs({"CityManager","PlayerManager","UnitManager","Players","Game","GameInfo","DB",
  "Events","GameEvents","Barbarians","GameConfiguration","PlayerConfigurations","SlotStatus",
  "UnitOperationTypes","CityCommandTypes","GameWorkspace"}) do
  local v = _G[n]
  P(string.format("%-22s %s", n, (v == nil) and "**nil**" or ("OK("..type(v)..")")))
end
""" + EPILOGUE

PROBE_API = PRELUDE + r"""
local function dump(name, obj, ms)
  P("== "..name.." ==")
  if obj == nil then P("  (nil)"); return end
  for _, m in ipairs(ms) do
    P(string.format("  %-34s %s", m, (obj[m] == nil) and "-- 不存在" or "存在"))
  end
end
dump("CityManager", CityManager, {"CreateCity","TransferCity","TransferCityToFreeCities",
  "SetAsCapital","SetAsOriginalCapital","DestroyDistrict","GetCity","GetCityAt","GetDistrictAt",
  "GetCommandTargets","GetOperationTargets","RequestCommand","RequestOperation",
  "CanStartCommand","CanStartOperation","AddCity","Found","Create"})
dump("PlayerManager", PlayerManager, {"AddPlayer","CreatePlayer","RemovePlayer","GetAliveMinorIDs",
  "GetAliveMinorsCount","GetAliveMajorIDs","GetAliveMajorsCount","GetMaxPlayers","GetPlayer",
  "GetAliveMajorIDs","SetPlayerType","GetAliveMinors"})
dump("UnitManager", UnitManager, {"CreateUnit","AddUnit","RequestOperation","CanStartOperation",
  "GetOperationTargets","KillUnit","GetUnitCount","GetUnits"})
dump("Game", Game, {"AddPlayer","CreatePlayer","RemovePlayer","GetMaxPlayers"})
dump("Barbarians", Barbarians, {"CreateTribeOfType","CreateSpecificTribe","CreateTribeUnits",
  "GetTribeConversionPoints","GetTribeConversionPointsRequired","GetTribeConversionDisabledHelp"})
""" + EPILOGUE

PROBE_WORLD = PRELUDE + r"""
P("== 计数 ==")
P("GetAliveMinorsCount = "..safe(function() return PlayerManager.GetAliveMinorsCount() end))
P("GetAliveMajorsCount = "..safe(function() return PlayerManager.GetAliveMajorsCount() end))
P("GetMaxPlayers       = "..safe(function() return PlayerManager.GetMaxPlayers() end))

P("")
P("== 全部玩家槽位 0..63（只列存在的）==")
local minor_set = {}
local ok, ids = pcall(function() return PlayerManager.GetAliveMinorIDs() end)
if ok and ids then for _, v in ipairs(ids) do minor_set[v] = true end end

for i = 0, 63 do
  local ok2, p = pcall(function() return Players[i] end)
  if ok2 and p ~= nil then
    local alive  = safe(function() return p:IsAlive() end)
    local ncity  = safe(function() return p:GetCities():GetCount() end)
    local civ    = safe(function() return HN(GameInfo.Civilizations, p:GetCivilizationType()) end)
    local lead   = safe(function() return HN(GameInfo.Leaders, p:GetLeaderType()) end)
    local ismin  = minor_set[i] and "MINOR" or "     "
    P(string.format("  slot %2d %s alive=%-5s cities=%-3s civ=%-32s leader=%s", i, ismin, alive, ncity, civ, lead))
  end
end

P("")
P("== 城邦池规模（配置库）==")
P("CityStates 总数 = "..safe(function()
  local r = DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates")
  return (r and #r) or "nil"
end))
P("按 Domain 分布 = "..safe(function()
  local r = DB.ConfigurationQuery("SELECT Domain, COUNT(*) AS N FROM CityStates GROUP BY Domain")
  if r == nil then return "nil" end
  local t = {}
  for _, row in ipairs(r) do t[#t+1] = tostring(row.Domain).."="..tostring(row.N) end
  return table.concat(t, ", ")
end))
""" + EPILOGUE


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-start", action="store_true", help="不触发开局")
    ap.add_argument("--wait", type=int, default=240, help="等待 GameCore 出现的秒数")
    args = ap.parse_args()

    print(f"[{time.strftime('%H:%M:%S')}] 连接 {HOST}:{PORT} ...")
    reader, writer = await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 8.0)
    print("TCP 已连接")

    await drain(reader, 0.4)
    await send(writer, TAG_HANDSHAKE, "APP:")
    m = await recv(reader, 8.0)
    print(f"游戏标识: {m[1] if m else '<无响应>'}")

    states = await lsq(reader, writer)
    print(f"状态数 {len(states)}: " + ", ".join(f"{i}={n}" for i, n in states[:6]) + " ...")
    name_of = dict(states)

    def find(pat):
        for i, n in states:
            if pat.lower() == n.lower():
                return i
        for i, n in states:
            if pat.lower() in n.lower():
                return i
        return None

    # ---- 1. 触发单机开局（同一连接内）---------------------------------
    if not args.no_start:
        mm = find("MainMenu")
        if mm is None:
            print("[!] 找不到 MainMenu 状态——游戏可能已在局内，跳过开局触发")
        else:
            print(f"\n[{time.strftime('%H:%M:%S')}] 在 state {mm} (MainMenu) 触发 OnPlayCiv6()")
            r, e = await run(reader, writer, mm, 'OnPlayCiv6() print("TRIGGERED")')
            emit("触发开局", r, e)

            print(f"\n[{time.strftime('%H:%M:%S')}] 轮询等待 GameCore 状态出现（最多 {args.wait}s）...")
            deadline = time.time() + args.wait
            gc = None
            while time.time() < deadline:
                await asyncio.sleep(10)
                try:
                    states = await lsq(reader, writer)
                except Exception as ex:
                    print(f"  LSQ 失败: {ex}")
                    continue
                name_of = dict(states)
                gc = find("GameCore")
                print(f"  [{time.strftime('%H:%M:%S')}] 状态数={len(states)} GameCore={gc}")
                if gc is not None:
                    break

            if gc is None:
                print("[!] 未等到 GameCore。仍尝试在 FrontEnd 上跑探针。")

    # ---- 2. 探针 ------------------------------------------------------
    states = await lsq(reader, writer)
    name_of = dict(states)
    print(f"\n[{time.strftime('%H:%M:%S')}] 最终状态数 {len(states)}")

    targets = []
    for want in ("GameCore", "InGame", "FrontEnd", "MainMenu"):
        i = find(want)
        if i is not None and i not in [t for t, _ in targets]:
            targets.append((i, name_of.get(i, want)))

    for idx, nm in targets:
        print(f"\n{'#' * 74}\n########## 状态 {idx}: {nm} ##########\n{'#' * 74}")
        for label, code in (("globals", PROBE_GLOBALS), ("api", PROBE_API), ("world", PROBE_WORLD)):
            r, e = await run(reader, writer, idx, code)
            emit(f"{nm} / {label}", r, e)

    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass
    print(f"\n[{time.strftime('%H:%M:%S')}] 会话结束（连接关闭）")


if __name__ == "__main__":
    asyncio.run(main())
