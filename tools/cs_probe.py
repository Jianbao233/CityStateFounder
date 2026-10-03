#!/usr/bin/env python3
"""临时探针：经 FireTuner(4318) 探测 Civ6 的 Lua API 与世界状态。

用途：「建立自选城邦」MOD 的可行性生死线验证。
  - CityManager.TransferCity 等绑定是否真实存在
  - 运行时建城 API 是否存在
  - 是否存在「0 座城的 minor civ 玩家」（= 休眠城邦槽位）
  - 城邦池规模 vs 实际在场 minor 数量
  - PlayerConfigurations / GameConfiguration 在哪些状态可用

默认**只读**：所有探测均不改变游戏状态。
`--act` 才会执行带副作用的动作（如 TransferCity），需显式指定。

用法：
  python _tmp_cs_probe.py --list
  python _tmp_cs_probe.py --probe api
  python _tmp_cs_probe.py --probe world --state GameCore
  python _tmp_cs_probe.py --probe slots
  python _tmp_cs_probe.py --eval 'print(1+1)'
"""

from __future__ import annotations

import argparse
import asyncio
import struct
import sys

HOST = "127.0.0.1"
PORT = 4318
HEADER_FMT = "<Ii"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
TAG_HANDSHAKE = 4
TAG_COMMAND = 3


# --------------------------------------------------------------------------
# 线协议
# --------------------------------------------------------------------------
async def send_message(writer, tag: int, payload: str) -> None:
    data = payload.encode("utf-8") + b"\x00"
    writer.write(struct.pack(HEADER_FMT, len(data), tag) + data)
    await writer.drain()


async def recv_message(reader, timeout: float):
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


async def drain(reader, timeout: float = 0.6) -> list[str]:
    out = []
    while True:
        m = await recv_message(reader, timeout)
        if m is None:
            break
        out.append(m[1])
    return out


async def discover_port(candidates=None):
    """⭐ 自动发现 FireTuner 端口。

    实测教训：引擎监听 4319 时，`Get-NetTCPConnection -State Listen` **查不到**它
    （表现为"4318-4325 全部无监听"却又能连上），所以无法靠"扫端口列表"定位；
    必须**逐个试连并握手**。端口会在 4318 被占用时顺延，游戏重启后还可能再变。
    """
    ports = candidates or list(range(4318, 4326))
    for p in ports:
        try:
            r, w = await asyncio.wait_for(asyncio.open_connection(HOST, p), 1.5)
        except Exception:
            continue
        try:
            await send_message(w, TAG_HANDSHAKE, "APP:")
            m = await recv_message(r, 2.5)
            if m is not None and "Civ6" in m[1]:
                print(f"[port] 自动发现 FireTuner 在 {p}")
                await close_conn(w)
                return p
        except Exception:
            pass
        await close_conn(w)
    return None


async def connect(port: int | None = None):
    """连接 FireTuner（带重试）。

    注意：不要设 SO_LINGER(1,0) 强制 RST——实测会让游戏侧 tuner 进入异常，
    后续连接报 WinError 64（"指定的网络名不再可用"）。用优雅关闭即可。

    ⚠️ 端口不固定：实测有一次引擎监听的是 **4319** 而不是 4318
    （4318 被占用时会顺延）。port=None 时自动发现。
    """
    p = port
    if p is None:
        p = await discover_port()
        if p is None:
            p = PORT
    last = None
    for _ in range(6):
        try:
            return await asyncio.wait_for(asyncio.open_connection(HOST, p), 6.0)
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


def parse_states(raw: str) -> list[tuple[int, str]]:
    """LSQ 返回的是 (索引, 名称) 交替的扁平列表 -> [(idx, name), ...]。

    实测样本：'0','Main State','1','DebugHotloadCache',...,'24','MainMenu',...
    其中数字才是 CMD 里要用的 state index。
    """
    parts = [s.strip() for s in raw.split("\x00") if s.strip()]
    if len(parts) <= 1 and "\n" in raw:
        parts = [s.strip() for s in raw.split("\n") if s.strip()]
    out: list[tuple[int, str]] = []
    i = 0
    while i < len(parts):
        a = parts[i]
        if a.isdigit() and i + 1 < len(parts):
            out.append((int(a), parts[i + 1]))
            i += 2
        else:
            out.append((len(out), a))
            i += 1
    return out


async def handshake(reader, writer):
    """握手（健壮版）。

    游戏在自动播放/报错洪水期间会往 tuner 猛推非请求输出，直接读 APP:/LSQ:
    的回包会读到洪水内容。做法：先长时间排空，再对 LSQ 重试直到拿到
    含 'Main State' 的可解析状态列表。
    """
    await drain(reader, 2.0)
    await send_message(writer, TAG_HANDSHAKE, "APP:")
    app = "<无响应>"
    for _ in range(5):
        m = await recv_message(reader, 3.0)
        if m is None:
            break
        if "Civ6" in m[1] or "Civilization" in m[1]:
            app = m[1]
            break
        app = m[1]

    states: list[tuple[int, str]] = []
    for _ in range(12):
        await send_message(writer, TAG_HANDSHAKE, "LSQ:")
        for _ in range(6):
            m = await recv_message(reader, 3.0)
            if m is None:
                break
            cand = parse_states(m[1])
            if any(n == "Main State" for _, n in cand):
                return app, cand
        await drain(reader, 0.8)
    return app, states


async def run_lua(reader, writer, state_index: int, code: str, timeout: float = 8.0):
    """在指定状态执行 Lua，返回 (显式响应, 追加的 print 输出)。

    洪水期间回包可能被淹没，故重试直到拿到非空响应或超时。
    """
    await send_message(writer, TAG_COMMAND, f"CMD:{state_index}:{code}")
    resp = None
    for _ in range(8):
        m = await recv_message(reader, timeout)
        if m is None:
            break
        if m[1] and not m[1].startswith("Runtime Error"):
            resp = m[1]
            break
        resp = m[1]
    extra = await drain(reader, 0.6)
    return resp, extra


def pick_state(states: list[tuple[int, str]], want: str | None) -> int:
    if want:
        w = want.lower()
        for idx, name in states:          # 先精确匹配
            if w == name.lower():
                return idx
        for idx, name in states:          # 再模糊匹配
            if w in name.lower():
                return idx
        print(f"[warn] 未找到状态 '{want}'，回退到 {states[0][0] if states else 0}")
    return states[0][0] if states else 0


# --------------------------------------------------------------------------
# Lua 探针
# --------------------------------------------------------------------------
PRELUDE = r"""
local function safe(f, ...) local ok, v = pcall(f, ...) if ok then return tostring(v) end return "ERR:"..tostring(v) end
local function HN(tbl, h)
  if h == nil then return "nil" end
  local r = tbl[h]
  if r == nil then return "?"..tostring(h) end
  return r.CivilizationType or r.LeaderType or r.UnitType or r.Type or tostring(h)
end
local OUT = {}
local function P(s) OUT[#OUT+1] = tostring(s) end
"""

EPILOGUE = r"""
print(table.concat(OUT, "\n"))
"""

PROBES: dict[str, str] = {}

# ---- 1. 全局对象是否存在 -------------------------------------------------
PROBES["globals"] = (
    PRELUDE
    + r"""
local names = {"CityManager","PlayerManager","UnitManager","GameConfiguration","PlayerConfigurations",
  "MapConfiguration","Players","Game","WorldBuilder","Barbarians","GameInfo","DB","Events","GameEvents",
  "Locale","Network","UnitOperationTypes","CityCommandTypes","UnitCommandTypes","PlayerTypes","SlotStatus"}
for _, n in ipairs(names) do
  local v = _G[n]
  P(string.format("%-22s %s", n, (v == nil) and "**nil**" or ("OK ("..type(v)..")")))
end
"""
    + EPILOGUE
)

# ---- 2. CityManager / PlayerManager / UnitManager 方法表 -----------------
PROBES["api"] = (
    PRELUDE
    + r"""
local function dump(objname, obj, methods)
  P("== " .. objname .. " ==")
  if obj == nil then P("  (对象不存在)"); return end
  for _, m in ipairs(methods) do
    local f = obj[m]
    P(string.format("  %-32s %s", m, (f == nil) and "-- 不存在" or ("存在 ("..type(f)..")")))
  end
end

dump("CityManager", CityManager, {
  "CreateCity","Create","Found","AddCity","TransferCity","TransferCityToFreeCities",
  "SetAsCapital","SetAsOriginalCapital","DestroyDistrict","GetCity","GetCityAt","GetDistrictAt",
  "GetCommandTargets","GetOperationTargets","RequestCommand","RequestOperation",
  "CanStartCommand","CanStartOperation","GetCities","GetNumCities"})

dump("PlayerManager", PlayerManager, {
  "AddPlayer","CreatePlayer","RemovePlayer","GetAliveMinorIDs","GetAliveMinorsCount",
  "GetAliveMajorIDs","GetAliveMajorsCount","GetPlayer","GetPlayers","SetPlayerType","GetMaxPlayers"})

dump("UnitManager", UnitManager, {
  "CreateUnit","AddUnit","RequestOperation","CanStartOperation","GetOperationTargets",
  "GetCommandTargets","RequestCommand","CanStartCommand","KillUnit","GetUnitCount"})
"""
    + EPILOGUE
)

# ---- 3. 世界状态：玩家 / 城邦 / 城市 -------------------------------------
PROBES["world"] = (
    PRELUDE
    + r"""
P("== 存活 minor civ 计数 ==")
P("GetAliveMinorsCount = " .. safe(function() return PlayerManager.GetAliveMinorsCount() end))
P("GetAliveMajorsCount = " .. safe(function() return PlayerManager.GetAliveMajorsCount() end))

local minors = nil
P("GetAliveMinorIDs = " .. safe(function() minors = PlayerManager.GetAliveMinorIDs() return #minors end))

P("")
P("== 全部玩家槽位 0..63 ==")
for i = 0, 63 do
  local ok, p = pcall(function() return Players[i] end)
  if ok and p ~= nil then
    local alive = safe(function() return p:IsAlive() end)
    local ncities = safe(function() return p:GetCities():GetCount() end)
    local civ = safe(function() return HN(GameInfo.Civilizations, p:GetCivilizationType()) end)
    local lead = safe(function() return HN(GameInfo.Leaders, p:GetLeaderType()) end)
    P(string.format("  slot %2d alive=%-5s cities=%-3s civ=%-34s leader=%s", i, alive, ncities, civ, lead))
  end
end

P("")
P("== 城邦池规模（配置库）==")
P("CityStates 全表 = " .. safe(function()
  local r = DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates")
  return (r and #r) or "nil"
end))
P("CityStates Domain 分布 = " .. safe(function()
  local r = DB.ConfigurationQuery("SELECT Domain, COUNT(*) AS N FROM CityStates GROUP BY Domain")
  if r == nil then return "nil" end
  local t = {}
  for _, row in ipairs(r) do t[#t+1] = row.Domain.."="..tostring(row.N) end
  return table.concat(t, ", ")
end))
"""
    + EPILOGUE
)

# ---- 4. 槽位/配置：FrontEnd 侧 ------------------------------------------
PROBES["slots"] = (
    PRELUDE
    + r"""
P("== GameConfiguration ==")
if GameConfiguration == nil then P("  (不存在)") else
  P("  GetValue(GAMEMODE_BARBARIAN_CLANS) = " .. safe(function() return tostring(GameConfiguration.GetValue("GAMEMODE_BARBARIAN_CLANS")) end))
  P("  GetValue(RULESET) = " .. safe(function() return tostring(GameConfiguration.GetValue("RULESET")) end))
end

P("")
P("== PlayerConfigurations ==")
if PlayerConfigurations == nil then P("  (不存在)") else
  for i = 0, 63 do
    local ok, pc = pcall(function() return PlayerConfigurations[i] end)
    if ok and pc ~= nil then
      P(string.format("  slot %2d status=%-14s leader=%-34s civ=%s", i,
        safe(function() return tostring(pc:GetSlotStatus()) end),
        safe(function() return tostring(pc:GetLeaderTypeName()) end),
        safe(function() return tostring(pc:GetCivilizationTypeName()) end)))
    end
  end
end

P("")
P("== SlotStatus 枚举 ==")
if SlotStatus ~= nil then
  for _, k in ipairs({"SS_BAD_SLOT","SS_CLOSED","SS_COMPUTER","SS_MAX_SLOT_STATUS","SS_OBSERVER","SS_OPEN","SS_TAKEN"}) do
    P(string.format("  %-24s %s", k, safe(function() return tostring(SlotStatus[k]) end)))
  end
else P("  (SlotStatus 不存在)") end
"""
    + EPILOGUE
)

# ---- 5. 引擎自带"造城邦"路径的挂钩点 ------------------------------------
PROBES["barb"] = (
    PRELUDE
    + r"""
P("== Barbarians / 蛮族氏族 ==")
if Barbarians == nil then P("  (Barbarians 不存在)") else
  for _, m in ipairs({"GetTribeConversionPoints","GetTribeConversionPointsRequired",
                      "GetTribeConversionDisabledHelp","CreateTribeOfType","CreateSpecificTribe","CreateTribeUnits"}) do
    P(string.format("  %-34s %s", m, (Barbarians[m] == nil) and "-- 不存在" or "存在"))
  end
end
P("")
P("== Events 中的氏族/城邦事件 ==")
if Events ~= nil then
  for _, e in ipairs({"BarbarianClanConversionEnabled","BarbarianClanConversionDisabled","CityAddedToMap","PlayerAdded"}) do
    P(string.format("  %-36s %s", e, (Events[e] == nil) and "-- 不存在" or "存在"))
  end
end
if GameEvents ~= nil then
  for _, e in ipairs({"BarbarianClanConversionEnabled","BarbarianClanConversionDisabled"}) do
    P(string.format("  GameEvents.%-28s %s", e, (GameEvents[e] == nil) and "-- 不存在" or "存在"))
  end
end
"""
    + EPILOGUE
)


# ---- 6. GameCore 侧 API 发现（容错版：逐个 pcall，任何一项失败不影响其余）----
PROBES["discover"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== Players[0] 候选方法（逐个 pcall）==")
local p0 = try(function() return Players[0] end)
P("Players[0] = "..p0)
local pcands = {"GetID","IsAlive","IsMinor","IsMajor","IsBarbarian","IsFreeCity","IsHuman","IsAI",
 "GetName","GetCivilizationType","GetLeaderType","GetCities","GetNumCities","GetCapitalCity",
 "GetTreasury","GetDiplomacy","GetUnits","GetTeam","GetProperty","SetProperty","GetResources",
 "GetTechs","GetCulture","GetInfluence","GetStats","GetPlayerColors","GetEra","GetScore",
 "GetNumUnits","GetCityCount","GetCityIds","GetCityList","GetMinorCivType","GetCivilization",
 "GetCity","GetCapital","IsAlive2"}
for _, m in ipairs(pcands) do
  local r = try(function() return type(Players[0][m]) end)
  if r ~= "nil" and r ~= "ERR" and r:sub(1,3) ~= "ERR" then
    P(string.format("  Player:%-24s %s", m, r))
  end
end

P("")
P("== 逐个调用探测（真调用，看返回值）==")
for _, m in ipairs({"IsAlive","IsMinor","IsMajor","GetID","GetNumCities","GetCapitalCity",
                    "GetCivilizationType","GetLeaderType","GetName"}) do
  P(string.format("  Players[0]:%-22s -> %s", m, try(function() return Players[0][m](Players[0]) end)))
end

P("")
P("== PlayerManager 计数与名单 ==")
P("GetAliveMinorsCount = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("GetAliveMajorsCount = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("minorIDs = "..try(function()
  local t = PlayerManager.GetAliveMinorIDs()
  local s = {}
  for _, v in ipairs(t) do s[#s+1] = tostring(v) end
  return "#"..#t.." ["..table.concat(s, ",").."]"
end))
P("majorIDs = "..try(function()
  local t = PlayerManager.GetAliveMajorIDs()
  local s = {}
  for _, v in ipairs(t) do s[#s+1] = tostring(v) end
  return "#"..#t.." ["..table.concat(s, ",").."]"
end))
""" + EPILOGUE
)

# ---- 7. 玩家明细（用 GameCore 侧正确访问器）----------------------------
PROBES["players"] = (
    PRELUDE
    + r"""
local function pname(id)
  local ok, v = pcall(function() return GameInfo.Players[id] end)
  if ok and v ~= nil then return tostring(v.CivilizationType).."/"..tostring(v.LeaderType) end
  return "?"
end

P("== 全部 64 槽位 ==")
for i = 0, 63 do
  local ok, p = pcall(function() return Players[i] end)
  if ok and p ~= nil then
    local alive = safe(function() return p:IsAlive() end)
    local minor = safe(function() return p:IsMinor() end)
    local nc    = safe(function() return p:GetNumCities() end)
    local cap   = safe(function() return p:GetCapitalCity() end)
    P(string.format("  slot %2d alive=%-6s minor=%-6s cities=%-4s capital=%-8s def=%s",
      i, alive, minor, nc, cap, pname(i)))
  end
end

P("")
P("== 城邦池（按 Domain）==")
P("全部行数 = "..safe(function()
  local r = DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates")
  return (r and #r) or "nil"
end))
for _, d in ipairs({"StandardCityStates","Expansion1CityStates","Expansion2CityStates"}) do
  P(string.format("  %-24s %s", d, safe(function()
    local r = DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates WHERE Domain = ?", d)
    return (r and #r) or "nil"
  end)))
end
"""
    + EPILOGUE
)


# ---- 8. TransferCity 签名 + City 对象方法面（只读探测，不改状态）--------
PROBES["transfer"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 90)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== TransferCity 签名探测（空参/错参，读错误信息）==")
P("TransferCity()          -> "..try(function() return CityManager.TransferCity() end))
P("TransferCity(0,1)       -> "..try(function() return CityManager.TransferCity(0, 1) end))
P("TransferCity(0,1,2)     -> "..try(function() return CityManager.TransferCity(0, 1, 2) end))
P("TransferCity(0,1,2,3)   -> "..try(function() return CityManager.TransferCity(0, 1, 2, 3) end))
P("TransferCityToFreeCities(0,1) -> "..try(function() return CityManager.TransferCityToFreeCities(0, 1) end))
P("DestroyDistrict()       -> "..try(function() return CityManager.DestroyDistrict() end))

P("")
P("== CityManager.GetCity 取一个真实城市 ==")
local city = nil
for pid = 0, 14 do
  local ok, c = pcall(function() return CityManager.GetCity(pid, 0) end)
  if ok and c ~= nil then city = c; P("找到城市: player="..pid.." city=0 -> "..tostring(c)); break end
end
if city == nil then
  P("(GetCity(pid,0) 未命中，遍历 cityID 1..3)")
  for pid = 0, 14 do
    for cid = 1, 3 do
      local ok, c = pcall(function() return CityManager.GetCity(pid, cid) end)
      if ok and c ~= nil then P("  命中 player="..pid.." city="..cid); city = c; break end
    end
    if city ~= nil then break end
  end
end

if city ~= nil then
  P("")
  P("== City 对象候选方法 ==")
  local ccands = {"GetID","GetOwner","GetName","GetX","GetY","GetPopulation","GetDamage","SetDamage",
   "DestroyCity","Destroy","Raze","SetOwner","Transfer","GetCityStateType","IsCapital","IsOriginalCapital",
   "GetPlot","GetBuildings","GetDistricts","GetNumDistricts","GetCulture","GetGold","GetProduction",
   "GetPurchaseYield","GetUnitCount","IsOccupied","GetOriginalOwner","SetPopulation","GetTurnsSinceFounded"}
  for _, m in ipairs(ccands) do
    local r = try(function() return type(city[m]) end)
    if r ~= "nil" then P(string.format("  City:%-26s %s", m, r)) end
  end
  P("")
  P("  真实调用: GetID -> "..try(function() return city:GetID() end))
  P("  真实调用: GetOwner -> "..try(function() return city:GetOwner() end))
  P("  真实调用: GetName -> "..try(function() return city:GetName() end))
end

P("")
P("== Barbarians 运行时方法面 ==")
for _, m in ipairs({"CreateTribeOfType","CreateSpecificTribe","CreateTribeUnits",
  "GetTribeConversionPoints","GetTribeConversionPointsRequired","GetTribeConversionDisabledHelp",
  "GetTribeIndexAtLocation","GetTribeType"}) do
  P(string.format("  Barbarians.%-36s %s", m, try(function() return type(Barbarians[m]) end)))
end
""" + EPILOGUE
)


# ---- 9. 遍历真实 City 对象，枚举其方法面（只读）------------------------
PROBES["cities"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 各玩家城市数（GetCities 可能是字段也可能是方法）==")
local sample = nil
for pid = 0, 14 do
  local ok, cities = pcall(function()
    local c = Players[pid].GetCities
    if type(c) == "function" then c = c(Players[pid]) end
    return c
  end)
  if ok and cities ~= nil then
    local n = 0
    local ok2, err2 = pcall(function()
      for city in cities do
        n = n + 1
        if sample == nil then sample = city end
      end
    end)
    if ok2 then
      P(string.format("  player %2d 城市数 = %d", pid, n))
    else
      P(string.format("  player %2d 集合不可迭代: %s", pid, tostring(err2):sub(1, 60)))
    end
  else
    P(string.format("  player %2d GetCities -> %s", pid, tostring(cities)))
  end
end

P("")
if sample == nil then
  P("(没取到城市对象，跳过 City 方法枚举)")
else
  P("== 样本 City 对象: "..tostring(sample).." ==")
  P("  GetID        -> "..try(function() return sample:GetID() end))
  P("  GetOwner     -> "..try(function() return sample:GetOwner() end))
  P("  GetName      -> "..try(function() return sample:GetName() end))
  P("  GetX / GetY  -> "..try(function() return sample:GetX() end).." / "..try(function() return sample:GetY() end))
  P("  GetPopulation-> "..try(function() return sample:GetPopulation() end))
  P("  IsCapital    -> "..try(function() return sample:IsCapital() end))
  P("")
  P("== City 候选方法面 ==")
  local ccands = {"GetID","GetOwner","GetName","GetX","GetY","GetPopulation","GetDamage","SetDamage",
   "DestroyCity","Destroy","Raze","SetOwner","Transfer","GetCityStateType","IsCapital","IsOriginalCapital",
   "GetPlot","GetBuildings","GetDistricts","GetNumDistricts","GetCulture","GetGold","GetProduction",
   "GetPurchaseYield","GetUnitCount","IsOccupied","GetOriginalOwner","SetPopulation","GetTurnsSinceFounded",
   "GetCitizens","GetGrowth","GetReligion","GetTrade","GetStats","GetInfluence","GetPower","GetWMDs"}
  for _, m in ipairs(ccands) do
    local r = try(function() return type(sample[m]) end)
    if r ~= "nil" then P(string.format("  City:%-26s %s", m, r)) end
  end
end

P("")
P("== 地图城邦数配置 ==")
P("MapSizes 行 = "..try(function()
  local r = DB.ConfigurationQuery("SELECT MapSizeType, NumCityStates FROM MapSizes")
  if r == nil then return "nil" end
  local t = {}
  for _, row in ipairs(r) do t[#t+1] = tostring(row.MapSizeType).."="..tostring(row.NumCityStates) end
  return table.concat(t, ", ")
end))
P("GlobalParameters 中氏族转化项 = "..try(function()
  local r = DB.ConfigurationQuery("SELECT Name, Value FROM GlobalParameters WHERE Name LIKE '%CONVERSION%' OR Name LIKE '%MINOR%'")
  if r == nil then return "nil" end
  local t = {}
  for _, row in ipairs(r) do t[#t+1] = tostring(row.Name).."="..tostring(row.Value) end
  return table.concat(t, ", ")
end))
""" + EPILOGUE
)


# ---- 10. City 对象获取与 CityTransferTypes 枚举（只读）-----------------
PROBES["cityobj"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 探查 Players[p].GetCities 的真实形态 ==")
local raw = Players[6].GetCities
P("type = "..type(raw))
if type(raw) == "table" then
  local n = 0
  for k, v in pairs(raw) do
    n = n + 1
    if n <= 8 then P(string.format("   [%s] = %s (%s)", tostring(k), tostring(v), type(v))) end
  end
  P("   键数 = "..n)
  P("   尝试 #raw = "..try(function() return #raw end))
  P("   尝试 raw[0] = "..try(function() return tostring(raw[0]) end))
  P("   尝试 raw[1] = "..try(function() return tostring(raw[1]) end))
  local mt = getmetatable(raw)
  P("   getmetatable(raw) = "..tostring(mt))
  if type(mt) == "table" then
    for k, v in pairs(mt) do P("     mt."..tostring(k).." ("..type(v)..")") end
  end
end

P("")
P("== 用 CityManager.GetCityAt 按坐标找城 ==")
-- 遍历地图找城市（限制范围，避免超时）
local found = {}
local w = Map and Map.GetGridWidth and Map:GetGridWidth() or 44
local h = Map and Map.GetGridHeight and Map:GetGridHeight() or 26
P(string.format("地图尺寸 = %s x %s", tostring(w), tostring(h)))
local cnt = 0
for x = 0, w - 1 do
  for y = 0, h - 1 do
    local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
    if ok and c ~= nil then
      cnt = cnt + 1
      if cnt <= 30 then
        found[#found+1] = c
        P(string.format("  城 @(%d,%d) owner=%s id=%s name=%s", x, y,
          try(function() return c:GetOwner() end),
          try(function() return c:GetID() end),
          try(function() return c:GetName() end)))
      end
    end
  end
end
P("GetCityAt 命中城市总数 = "..cnt)

P("")
if #found > 0 then
  local c = found[1]
  P("== 样本 City 对象方法面 ==")
  local ccands = {"GetID","GetOwner","GetName","GetX","GetY","GetPopulation","GetDamage","SetDamage",
   "DestroyCity","Destroy","Raze","SetOwner","Transfer","IsCapital","IsOriginalCapital",
   "GetPlot","GetBuildings","GetDistricts","GetNumDistricts","GetUnitCount","IsOccupied",
   "GetOriginalOwner","SetPopulation","GetCitizens","GetGrowth","GetReligion","GetTrade",
   "GetStats","GetInfluence","GetCulture","GetGold","GetProduction","GetPurchaseYield"}
  for _, m in ipairs(ccands) do
    local r = try(function() return type(c[m]) end)
    if r ~= "nil" then P(string.format("  City:%-26s %s", m, r)) end
  end
  P("")
  P("  样本真值: GetID="..try(function() return c:GetID() end)
    .." GetOwner="..try(function() return c:GetOwner() end)
    .." GetName="..try(function() return c:GetName() end)
    .." GetPopulation="..try(function() return c:GetPopulation() end))
end

P("")
P("== CityTransferTypes 枚举（GameInfo）==")
for _, t in ipairs({"CityTransferTypes","CityTransferTypeMatches","CityStates","CityStateTypes"}) do
  P(string.format("  GameInfo.%-24s %s", t, try(function() return type(GameInfo[t]) end)))
end
P("CityTransferTypes 内容 = "..try(function()
  local t = {}
  for row in GameInfo.CityTransferTypes() do t[#t+1] = tostring(row.CityTransferType) end
  return "#"..#t.." ["..table.concat(t, ", ").."]"
end))
""" + EPILOGUE
)


# ---- 11. 钉死 City 对象的获取方式（只读）-------------------------------
PROBES["getcity"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

for _, pid in ipairs({0, 6}) do
  P("===== player "..pid.." =====")
  local p = Players[pid]
  P("  type(p)                 = "..try(function() return type(p) end))
  P("  type(p.GetCities)       = "..try(function() return type(p.GetCities) end))
  P("  p:GetCities()           = "..try(function() return tostring(p:GetCities()) end))
  P("  p.GetCities(p)          = "..try(function() return tostring(p.GetCities(p)) end))
  P("  p.GetCities()           = "..try(function() return tostring(p.GetCities()) end))

  local ok, cities = pcall(function() return p:GetCities() end)
  P("  pcall(p:GetCities())    ok="..tostring(ok).."  val="..tostring(cities))
  if ok and cities ~= nil then
    P("  type(cities)            = "..type(cities))
    local n1 = 0
    local o1, e1 = pcall(function() for _ in cities do n1 = n1 + 1 end end)
    P("  泛型 for 迭代           ok="..tostring(o1).." n="..n1.." err="..tostring(e1):sub(1, 60))
    local n2 = 0
    local o2, e2 = pcall(function() for _ in pairs(cities) do n2 = n2 + 1 end end)
    P("  pairs 迭代              ok="..tostring(o2).." n="..n2.." err="..tostring(e2):sub(1, 60))
    P("  #cities                 = "..try(function() return #cities end))
    P("  cities.GetCount         = "..try(function() return type(cities.GetCount) end))
    P("  cities:GetCount()       = "..try(function() return cities:GetCount() end))
    local mt = getmetatable(cities)
    P("  getmetatable(cities)    = "..tostring(mt))
    if type(mt) == "table" then
      for k, v in pairs(mt) do P("     mt."..tostring(k).." ("..type(v)..")") end
    end
    -- 试着取出一个 city
    local sample = nil
    pcall(function() for c in cities do sample = c break end end)
    if sample == nil then pcall(function() for _, v in pairs(cities) do sample = v break end end) end
    if sample == nil then sample = cities[0] or cities[1] end
    P("  sample city             = "..tostring(sample))
    if sample ~= nil then
      P("  sample:GetID()          = "..try(function() return sample:GetID() end))
      P("  sample:GetOwner()       = "..try(function() return sample:GetOwner() end))
      P("  sample:GetName()        = "..try(function() return sample:GetName() end))
      P("  -- City 方法面 --")
      for _, m in ipairs({"GetID","GetOwner","GetName","GetX","GetY","GetPopulation","DestroyCity",
        "Destroy","Raze","SetOwner","IsCapital","GetPlot","GetBuildings","GetDistricts",
        "GetUnitCount","IsOccupied","GetOriginalOwner"}) do
        local r = try(function() return type(sample[m]) end)
        if r ~= "nil" then P("     City:"..m.." = "..r) end
      end
    end
  end
  P("")
end

P("== UnitManager / Units 侧（找单位对象）==")
for _, n in ipairs({"UnitManager","Units","UnitOperations","CityManager"}) do
  P(string.format("  %-16s %s", n, try(function() return type(_G[n]) end)))
end
P("  p:GetUnits() = "..try(function() return tostring(Players[0]:GetUnits()) end))
""" + EPILOGUE
)


# ---- 12. 实测 PlayerCities:Create（推翻性验证）------------------------
# 依据：Firaxis 官方澳洲场景 DLC\AustraliaScenario\Scripts\AustraliaScenario.lua:1344-1346
#   local pSydneyPlayer = Players[eSydney];
#   pSydneyPlayer:GetCities():Create(51, 11);
# 若成立，则「运行时为城邦玩家建城」原生可行，方案大幅简化。
PROBES["createcity"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 80)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 城邦玩家与 GetCities 形态 ==")
local ids = PlayerManager.GetAliveMinorIDs()
P("GetAliveMinorIDs 数量 = "..#ids)
for i = 1, math.min(#ids, 4) do
  local pid = ids[i]
  P(string.format("  minor id=%d  type(GetCities)=%s  GetCities()=%s",
    pid,
    try(function() return type(Players[pid].GetCities) end),
    try(function() return tostring(Players[pid]:GetCities()) end)))
end

P("")
P("== 找候选空地（陆地 + 无主）==")
local cand = {}
local W, H = 44, 26
for x = 0, W - 1 do
  for y = 0, H - 1 do
    local plot = Map.GetPlot(x, y)
    if plot ~= nil then
      local w = try(function() return plot:IsWater() end)
      local o = try(function() return plot:GetOwner() end)
      if w == "false" and o == "-1" then
        cand[#cand + 1] = {x, y}
        if #cand >= 6 then break end
      end
    end
  end
  if #cand >= 6 then break end
end
P("候选数量 = "..#cand)
for i, c in ipairs(cand) do P(string.format("  (%d,%d)", c[1], c[2])) end

P("")
if #cand == 0 then P("(无候选地块，跳过建城测试)") else
  local pid = ids[1]
  local tx, ty = cand[1][1], cand[1][2]
  P("== 实测 Players["..pid.."]:GetCities():Create("..tx..","..ty..") ==")
  local before = try(function() return tostring(Players[pid]:GetCities()) end)
  P("  调用前 GetCities = "..before)

  local ok, err = pcall(function() Players[pid]:GetCities():Create(tx, ty) end)
  P("  调用结果 ok="..tostring(ok).."  err="..tostring(err):sub(1, 120))

  local after = try(function() return tostring(Players[pid]:GetCities()) end)
  P("  调用后 GetCities = "..after)

  -- 复查该格是否变成城市
  P("  该格城市 = "..try(function() return tostring(CityManager.GetCityAt(tx, ty)) end))
  P("  该格归属 = "..try(function() return Map.GetPlot(tx, ty):GetOwner() end))
end

P("")
P("== PlayerCities 对象候选方法面 ==")
local pc = Players[ids[1]]:GetCities()
P("type = "..type(pc))
for _, m in ipairs({"Create","GetCount","GetNumCities","Find","GetCity","GetCapitalCity"}) do
  P(string.format("  PlayerCities.%-16s %s", m, try(function() return type(pc[m]) end)))
end
""" + EPILOGUE
)


# ---- 13. 建城后的验证 + City 对象方法面（只读）------------------------
PROBES["verifycity"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 城邦城市数 ==")
local ids = PlayerManager.GetAliveMinorIDs()
for i = 1, #ids do
  local pid = ids[i]
  P(string.format("  minor %2d  cities=%s  capital=%s", pid,
    try(function() return Players[pid]:GetCities():GetCount() end),
    try(function() return tostring(Players[pid]:GetCities():GetCapitalCity()) end)))
end

P("")
P("== 主文明城市数 ==")
local mids = PlayerManager.GetAliveMajorIDs()
for i = 1, #mids do
  local pid = mids[i]
  P(string.format("  major %2d  cities=%s", pid,
    try(function() return Players[pid]:GetCities():GetCount() end)))
end

P("")
P("== 取 City 对象（GetCityAt）并枚举方法面 ==")
local city = nil
for x = 0, 20 do
  for y = 15, 25 do
    local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
    if ok and c ~= nil then city = c; P("命中城市 @("..x..","..y..")") break end
  end
  if city ~= nil then break end
end
if city == nil then P("(未取到 City 对象)") else
  P("  type = "..try(function() return type(city) end))
  P("  GetID         -> "..try(function() return city:GetID() end))
  P("  GetOwner      -> "..try(function() return city:GetOwner() end))
  P("  GetName       -> "..try(function() return city:GetName() end))
  P("  GetX/GetY     -> "..try(function() return city:GetX() end).." / "..try(function() return city:GetY() end))
  P("  GetPopulation -> "..try(function() return city:GetPopulation() end))
  P("  IsCapital     -> "..try(function() return city:IsCapital() end))
  P("")
  P("  -- 候选方法面 --")
  for _, m in ipairs({"GetID","GetOwner","GetName","GetX","GetY","GetPopulation","SetPopulation",
    "DestroyCity","Destroy","Raze","SetOwner","IsCapital","IsOriginalCapital","GetOriginalOwner",
    "GetPlot","GetBuildings","GetDistricts","GetNumDistricts","GetUnitCount","IsOccupied",
    "GetCulture","GetGold","GetProduction","GetPurchaseYield","GetTurnsSinceFounded","GetCitizens"}) do
    local r = try(function() return type(city[m]) end)
    if r ~= "nil" then P("     City:"..m.." = "..r) end
  end
end
""" + EPILOGUE
)


# ---- 14. ⭐ 决定性测试：为「0 城休眠城邦」建城 --------------------------
# 若成立 ⇒ 「预留城邦槽 + 运行时激活」路线原生可行。
PROBES["activate"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 对局状态 ==")
P("  GetCurrentGameTurn = "..try(function() return Game.GetCurrentGameTurn() end))
P("  GetStartTurn       = "..try(function() return Game.GetStartTurn() end))

P("")
P("== 找 0 城城邦 + 找空地 ==")
local zeroCityMinors = {}
local ids = PlayerManager.GetAliveMinorIDs()
for i = 1, #ids do
  local pid = ids[i]
  local n = tonumber(try(function() return Players[pid]:GetCities():GetCount() end))
  if n == 0 then zeroCityMinors[#zeroCityMinors + 1] = pid end
end
P("  0 城城邦 = "..#zeroCityMinors.." 个")

-- 找空地（陆地 + 无主）；GetCityAt 对无城地块会抛异常，故不用于筛选
local cand = {}
for x = 0, 43 do
  for y = 0, 25 do
    local plot = Map.GetPlot(x, y)
    if plot ~= nil then
      local w = try(function() return plot:IsWater() end)
      local o = try(function() return plot:GetOwner() end)
      if w == "false" and o == "-1" then
        cand[#cand + 1] = {x, y}
      end
    end
  end
end
P("  可用空地 = "..#cand)

P("")
if #zeroCityMinors == 0 then
  P("(无 0 城城邦，跳过)")
else
  P("== 收集全部城市坐标 ==")
  local cityPlots = {}
  for x = 0, 43 do
    for y = 0, 25 do
      local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
      if ok and c ~= nil then cityPlots[#cityPlots + 1] = {x, y} end
    end
  end
  P("  场上城市数 = "..#cityPlots)
  for i, cp in ipairs(cityPlots) do
    if i <= 8 then P(string.format("    (%d,%d)", cp[1], cp[2])) end
  end

  -- 找距所有城市 >= 4 格的空地
  local function farEnough(x, y)
    for _, cp in ipairs(cityPlots) do
      local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
      local d = math.max(dx, dy) + math.min(dx, dy) * 0.5
      if d < 4 then return false end
    end
    return true
  end

  local far = {}
  for _, t in ipairs(cand) do
    if farEnough(t[1], t[2]) then far[#far + 1] = t end
  end
  P("  距所有城市 >=4 的空地 = "..#far)

  P("")
  P("== ⭐ 对 0 城城邦在【合法地块】建城 ==")
  for k = 1, math.min(3, #far) do
    local pid = zeroCityMinors[k]
    local t = far[k]
    P(string.format("  城邦 %d @(%d,%d):", pid, t[1], t[2]))
    P("    建城前 cities = "..try(function() return Players[pid]:GetCities():GetCount() end))
    local ok, err = pcall(function() Players[pid]:GetCities():Create(t[1], t[2]) end)
    P("    Create -> ok="..tostring(ok).." err="..tostring(err):sub(1, 80))
    P("    建城后 cities = "..try(function() return Players[pid]:GetCities():GetCount() end))
    P("    该格归属 = "..try(function() return Map.GetPlot(t[1], t[2]):GetOwner() end))
    P("    仍存活   = "..try(function() return Players[pid]:IsAlive() end))
  end

  P("")
  P("== 复查全部城邦 ==")
  local ids2 = PlayerManager.GetAliveMinorIDs()
  P("  存活城邦数 = "..#ids2)
  for i = 1, #ids2 do
    P(string.format("    minor %2d cities=%s", ids2[i],
      try(function() return Players[ids2[i]]:GetCities():GetCount() end)))
  end
end
""" + EPILOGUE
)


# ---- 15. U1：槽位上限研究 --------------------------------------------
PROBES["defines"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== GameDefines 中与玩家/城邦相关的常量 ==")
local n, hits = 0, 0
for k, v in pairs(GameDefines) do
  n = n + 1
  local ks = tostring(k)
  if ks:match("PLAYER") or ks:match("CIV") or ks:match("MINOR") or ks:match("CITY") or ks:match("MAJOR") then
    P(string.format("  GameDefines.%-40s = %s", ks, tostring(v)))
    hits = hits + 1
  end
end
P("  (GameDefines 总键数 = "..n.."，命中 "..hits.." 个)")

P("")
P("== 直接点名 ==")
for _, k in ipairs({"MAX_PLAYERS","MAX_MAJOR_CIVS","MAX_MINOR_CIVS","MAX_CITY_STATES",
                    "BARBARIAN_PLAYER","FREE_CITY_PLAYER"}) do
  P(string.format("  %-24s %s", k, try(function() return GameDefines[k] end)))
end

P("")
P("== 本局槽位占用（0..63）==")
local exist, alive = 0, 0
local firstDead = nil
for i = 0, 63 do
  local ok, p = pcall(function() return Players[i] end)
  if ok and p ~= nil then
    exist = exist + 1
    local a = try(function() return p:IsAlive() end)
    if a == "true" then alive = alive + 1 else if firstDead == nil then firstDead = i end end
  end
end
P("  存在对象的槽 = "..exist)
P("  存活的槽     = "..alive)
P("  首个非存活槽 = "..tostring(firstDead))
P("  GetAliveMajorsCount = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  GetAliveMinorsCount = "..try(function() return PlayerManager.GetAliveMinorsCount() end))

P("")
P("== 地图配置中的城邦数参数 ==")
if MapConfiguration == nil then P("  (MapConfiguration 在本状态不可用)") else
  for _, k in ipairs({"MAP_MIN_MINOR_PLAYERS","MAP_MAX_MINOR_PLAYERS","MAP_SIZE",
                      "MAP_SCRIPT","RANDOM_SEED"}) do
    P(string.format("  MapConfiguration[%-24s] = %s", k, try(function() return MapConfiguration.GetValue(k) end)))
  end
end
if GameConfiguration == nil then P("  (GameConfiguration 在本状态不可用)") else
  P("  GameConfiguration RULESET = "..try(function() return GameConfiguration.GetValue("RULESET") end))
end
"""
    + EPILOGUE
)

# ---- 16. U4：存档（须在 InGame 状态执行）-------------------------------
PROBES["savegame"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 存档前置条件 ==")
P("  UI.HasFeature('Saving')      = "..try(function() return UI.HasFeature("Saving") end))
P("  Game.GetLocalPlayer()        = "..try(function() return Game.GetLocalPlayer() end))
P("  Network.GetGameConfigurationSaveType() = "..try(function() return Network.GetGameConfigurationSaveType() end))
P("  SaveLocations.LOCAL_STORAGE  = "..try(function() return SaveLocations.LOCAL_STORAGE end))
P("  CanLocalPlayerSaveGame()     = "..try(function() return CanLocalPlayerSaveGame() end))

P("")
P("== 执行存档 ==")
local gameFile = {}
gameFile.Name = "CSTEST_01"
gameFile.Location = SaveLocations.LOCAL_STORAGE
gameFile.Type = Network.GetGameConfigurationSaveType()
gameFile.IsAutosave = false
gameFile.IsQuicksave = false
P("  gameFile.Name = "..tostring(gameFile.Name))
P("  gameFile.Type = "..tostring(gameFile.Type))
P("  调用 Network.SaveGame(gameFile) -> "..try(function() return Network.SaveGame(gameFile) end))
"""
    + EPILOGUE
)


# ---- 17. 配置库可读性 + MapSizes / CityStates 实测 ---------------------
PROBES["configdb"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== DB / GameInfo 表可见性 ==")
P("  GameInfo.MapSizes   = "..try(function() return type(GameInfo.MapSizes) end))
P("  GameInfo.CityStates = "..try(function() return type(GameInfo.CityStates) end))

P("")
P("== DB.ConfigurationQuery：MapSizes ==")
P(try(function()
  local r = DB.ConfigurationQuery("SELECT MapSizeType, MinPlayers, MaxPlayers, MinCityStates, MaxCityStates, DefaultCityStates FROM MapSizes ORDER BY SortIndex")
  if r == nil then return "  (nil)" end
  local t = {}
  for _, row in ipairs(r) do
    t[#t+1] = string.format("  %-22s players=%s..%s  CS=%s..%s (def %s)",
      tostring(row.MapSizeType), tostring(row.MinPlayers), tostring(row.MaxPlayers),
      tostring(row.MinCityStates), tostring(row.MaxCityStates), tostring(row.DefaultCityStates))
  end
  return table.concat(t, "\n")
end))

P("")
P("== DB.ConfigurationQuery：CityStates 池（按 Domain）==")
P(try(function()
  local r = DB.ConfigurationQuery("SELECT Domain, COUNT(*) AS N FROM CityStates GROUP BY Domain")
  if r == nil then return "  (nil)" end
  local t = {}
  for _, row in ipairs(r) do t[#t+1] = "  "..tostring(row.Domain).." = "..tostring(row.N) end
  return table.concat(t, "\n")
end))

P("")
P("== 抽样：XP2 池前 5 个城邦 ==")
P(try(function()
  local r = DB.ConfigurationQuery("SELECT CivilizationType, Name, Icon, CityStateCategory, Bonus FROM CityStates WHERE Domain = ? LIMIT 5", "Expansion2CityStates")
  if r == nil then return "  (nil)" end
  local t = {}
  for _, row in ipairs(r) do
    t[#t+1] = string.format("  %-32s %-36s %-32s %s", tostring(row.CivilizationType),
      tostring(row.Name), tostring(row.Icon), tostring(row.CityStateCategory))
  end
  return table.concat(t, "\n")
end))
"""
    + EPILOGUE
)


# ---- 18. 状态快照（存读档前后对比用）----------------------------------
PROBES["snapshot"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 对局标识 ==")
P("  Turn         = "..try(function() return Game.GetCurrentGameTurn() end))
P("  LocalPlayer  = "..try(function() return Game.GetLocalPlayer() end))
P("  RANDOM_SEED  = "..try(function() return MapConfiguration.GetValue("RANDOM_SEED") end))

P("")
P("== 全部存活玩家的城市清单 ==")
local ids = PlayerManager.GetAliveMajorIDs()
local mids = PlayerManager.GetAliveMinorIDs()
local all = {}
for _, v in ipairs(ids) do all[#all+1] = {v, "MAJOR"} end
for _, v in ipairs(mids) do all[#all+1] = {v, "MINOR"} end

local total = 0
for _, e in ipairs(all) do
  local pid, kind = e[1], e[2]
  local n = tonumber(try(function() return Players[pid]:GetCities():GetCount() end)) or 0
  total = total + n
  P(string.format("  %-5s %2d  cities=%d  alive=%s", kind, pid, n,
    try(function() return Players[pid]:IsAlive() end)))
  if n > 0 then
    local pcs = Players[pid]:GetCities()
    -- PlayerCities 无 GetCity，用 GetCityAt 全图扫（成本可控）
    for x = 0, 43 do
      for y = 0, 25 do
        local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
        if ok and c ~= nil then
          local owner = tonumber(try(function() return c:GetOwner() end))
          if owner == pid then
            P(string.format("        @(%2d,%2d) id=%-8s pop=%-3s name=%s", x, y,
              try(function() return c:GetID() end),
              try(function() return c:GetPopulation() end),
              try(function() return c:GetName() end)))
          end
        end
      end
    end
  end
end
P("  场上城市总数 = "..total)
P("  barbarian(62) alive = "..try(function() return Players[62]:IsAlive() end))
P("  freecity (63) alive = "..try(function() return Players[63]:IsAlive() end))
"""
    + EPILOGUE
)


# ---- 19. U3：城邦「原生性」检查 ---------------------------------------
# 判据来自 MirrorMapDemo_CityStatesPatch.lua:167-191
#   player:IsAlive() and not IsBarbarian() and not IsFreeCities()
#   and player:GetInfluence():CanReceiveInfluence()
PROBES["nativeness"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local ids = PlayerManager.GetAliveMinorIDs()
P("== 存活城邦 "..#ids.." 个，逐个检查原生性 ==")
for i = 1, #ids do
  local pid = ids[i]
  local p = Players[pid]
  local n = tonumber(try(function() return p:GetCities():GetCount() end)) or 0

  P("")
  P(string.format("--- 城邦 %d（cities=%d）---", pid, n))
  P("  IsAlive        = "..try(function() return p:IsAlive() end))
  P("  IsMajor        = "..try(function() return p:IsMajor() end))
  P("  IsBarbarian    = "..try(function() return p:IsBarbarian() end))
  P("  IsFreeCities   = "..try(function() return p:IsFreeCities() end))
  P("  IsHuman        = "..try(function() return p:IsHuman() end))

  local infl = try(function() return tostring(p:GetInfluence()) end)
  P("  GetInfluence   = "..infl)
  P("  ⭐ CanReceiveInfluence = "..try(function() return p:GetInfluence():CanReceiveInfluence() end))
  P("  GetTokensReceived(0)   = "..try(function() return p:GetInfluence():GetTokensReceived(0) end))
  P("  GetSuzerain            = "..try(function() return p:GetInfluence():GetSuzerain() end))

  -- 配置侧
  if PlayerConfigurations ~= nil then
    local cfg = PlayerConfigurations[pid]
    P("  LeaderTypeName = "..try(function() return cfg:GetLeaderTypeName() end))
    P("  CivTypeName    = "..try(function() return cfg:GetCivilizationTypeName() end))
    local lt = try(function() return cfg:GetLeaderTypeName() end)
    if lt ~= "nil" and lt:sub(1,3) ~= "ERR" then
      P("  Leaders[lt].InheritFrom = "..try(function()
        local li = GameInfo.Leaders[lt]
        return li ~= nil and li.InheritFrom or "nil"
      end))
    end
  else
    P("  (PlayerConfigurations 在本状态不可用)")
  end

  -- 城邦面板条目字段（官方 CityStates UI 的 m_kCityStates 结构）
  P("  -- 面板所需字段可得性 --")
  P("    城邦类型(经 InheritFrom) = "..try(function()
    local lt = PlayerConfigurations[pid]:GetLeaderTypeName()
    local li = GameInfo.Leaders[lt]
    local inh = li ~= nil and li.InheritFrom or nil
    if inh == nil then return "nil" end
    return tostring(inh):gsub("LEADER_MINOR_CIV_", "")
  end))
  P("    图标可用性 = "..try(function()
    local ct = PlayerConfigurations[pid]:GetCivilizationTypeName()
    return "ICON_"..tostring(ct)
  end))
end

P("")
P("== 使者/宗主 侧（本地玩家视角）==")
P("  Players[0]:GetInfluence() = "..try(function() return tostring(Players[0]:GetInfluence()) end))
P("  GetTokensToGive           = "..try(function() return Players[0]:GetInfluence():GetTokensToGive() end))
P("  CanGiveTokensToPlayer(6)  = "..try(function() return Players[0]:GetInfluence():CanGiveTokensToPlayer(6) end))
"""
    + EPILOGUE
)


# ---- 20. 回合推进（须在 InGame 状态）----------------------------------
PROBES["endturn"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 回合推进 API 可用性 ==")
P("  DoEndTurn                = "..try(function() return type(DoEndTurn) end))
P("  UI.CanEndTurn            = "..try(function() return type(UI.CanEndTurn) end))
P("  UI.CanEndTurn()          = "..try(function() return UI.CanEndTurn() end))
P("  Game.IsAllowTacticalCommands = "..try(function() return type(Game.IsAllowTacticalCommands) end))
P("  Game.GetCurrentGameTurn()= "..try(function() return Game.GetCurrentGameTurn() end))
P("  Game.GetLocalPlayer()    = "..try(function() return Game.GetLocalPlayer() end))

P("")
P("== 执行 DoEndTurn() ×3 ==")
for i = 1, 3 do
  P("  第 "..i.." 次 -> "..try(function() return DoEndTurn() end))
end
"""
    + EPILOGUE
)


# ---- 21. 自动播放（推进回合的正解）------------------------------------
# 依据 Base\Assets\UI\ActionPanel.lua:1112 注释 "When autoplay first starts;
# kicked off from the Tuner." + AutoplayManager 的 4 个方法。
PROBES["autoplay"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== AutoplayManager API ==")
P("  AutoplayManager                    = "..try(function() return type(AutoplayManager) end))
for _, m in ipairs({"SetActive","SetTurns","SetObserveAsPlayer","SetReturnAsPlayer"}) do
  P(string.format("  AutoplayManager.%-20s = %s", m, try(function() return type(AutoplayManager[m]) end)))
end
P("  Automation.IsActive                = "..try(function() return type(Automation.IsActive) end))
P("  Automation.IsActive()              = "..try(function() return Automation.IsActive() end))

P("")
P("== 启动自动播放 10 回合 ==")
-- ⚠️ 四调用齐全（依据 Automation_DailySmokeTest.lua:194-198）；
--    漏 SetReturnAsPlayer 时不会停（实测一路跑到 turn 130）
P("  SetTurns(10)           -> "..try(function() return AutoplayManager.SetTurns(10) end))
P("  SetReturnAsPlayer(0)   -> "..try(function() return AutoplayManager.SetReturnAsPlayer(0) end))
P("  SetObserveAsPlayer(0)  -> "..try(function() return AutoplayManager.SetObserveAsPlayer(0) end))
P("  SetActive(true)        -> "..try(function() return AutoplayManager.SetActive(true) end))
P("  (已发起，回合将在后台自动推进)")
"""
    + EPILOGUE
)


# ---- 22. U2：休眠城邦模拟（把城邦送下地图）----------------------------
# 复刻 Free City States 的机制，但用 FireTuner 直接做，无需写 MOD：
#   UnitManager.InitUnit(pid, "UNIT_SETTLER", -1, -1)   -- 地图外给一个移民
#   UnitManager.Kill(pUnit)                             -- 杀掉地图上的单位
# 之后用 AutoplayManager 跑回合，观察它能否稳定存活。
PROBES["dormant"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function unitList(pid)
  local out = {}
  local ok, pUnits = pcall(function() return Players[pid]:GetUnits() end)
  if not ok or pUnits == nil then return out end
  local ok2 = pcall(function()
    for ii, pUnit in pUnits:Members() do
      local x = tonumber(try(function() return pUnit:GetX() end)) or -99
      local y = tonumber(try(function() return pUnit:GetY() end)) or -99
      local ut = try(function() return GameInfo.Units[pUnit:GetType()].UnitType end)
      out[#out + 1] = string.format("%s@(%d,%d)", tostring(ut), x, y)
    end
  end)
  if not ok2 then out[#out + 1] = "(Members 迭代失败)" end
  return out
end

local function describe(pid, tag)
  local p = Players[pid]
  local n = tonumber(try(function() return p:GetCities():GetCount() end)) or -1
  local cap = try(function() return tostring(p:GetCities():GetCapitalCity()) end)
  local us = unitList(pid)
  P(string.format("  %s 城邦 %2d  alive=%-5s cities=%d capital=%s units=%d [%s]",
    tag, pid, try(function() return p:IsAlive() end), n, cap, #us, table.concat(us, " ")))
  return n
end

P("== 回合 ==")
P("  Game.GetCurrentGameTurn() = "..try(function() return Game.GetCurrentGameTurn() end))

P("")
P("== 目标：把「最后一个城邦」送下地图（其余留作对照）==")
local ids = PlayerManager.GetAliveMinorIDs()
P("  存活城邦 "..#ids.." 个")
for i = 1, #ids do describe(ids[i], "BEFORE") end

P("")
if #ids < 2 then
  P("(城邦不足 2 个，跳过)")
else
  local target = ids[#ids]
  P("== 对城邦 "..target.." 执行休眠 ==")

  -- ① 地图外给一个移民（保证不灭亡）
  P("  ① InitUnit("..target..", UNIT_SETTLER, -1, -1) -> "..
    try(function() return UnitManager.InitUnit(target, "UNIT_SETTLER", -1, -1) end))

  -- ② 杀掉地图上的单位
  local killed = 0
  local ok, pUnits = pcall(function() return Players[target]:GetUnits() end)
  if ok and pUnits ~= nil then
    pcall(function()
      for ii, pUnit in pUnits:Members() do
        local x = tonumber(try(function() return pUnit:GetX() end)) or -99
        local y = tonumber(try(function() return pUnit:GetY() end)) or -99
        if x >= 0 or y >= 0 then
          UnitManager.Kill(pUnit, false)
          killed = killed + 1
        end
      end
    end)
  end
  P("  ② 杀掉地图上的单位 "..killed.." 个")

  -- ③ 判定是否成为「休眠城邦」
  P("  ③ 休眠判定：")
  local cap = try(function() return tostring(Players[target]:GetCities():GetCapitalCity()) end)
  local us = unitList(target)
  local hasOffmap = false
  local hasOnmap = false
  for _, u in ipairs(us) do
    local x = tonumber(u:match("@%((%-?%d+),")) or 0
    if x < 0 then hasOffmap = true else hasOnmap = true end
  end
  P("     capital      = "..cap)
  P("     地图外单位   = "..tostring(hasOffmap))
  P("     地图上单位   = "..tostring(hasOnmap))
  P("     → 休眠城邦？ = "..tostring(cap == "nil" and hasOffmap and not hasOnmap))

  P("")
  P("== 休眠后 ==")
  for i = 1, #ids do describe(ids[i], "AFTER ") end
end
"""
    + EPILOGUE
)


# ---- 23. U2/U5/U6/U7 综合测试：布置 ------------------------------------
PROBES["u567_setup"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function unitList(pid)
  local out = {}
  local ok, pUnits = pcall(function() return Players[pid]:GetUnits() end)
  if not ok or pUnits == nil then return out end
  pcall(function()
    for ii, pUnit in pUnits:Members() do
      local x = tonumber(try(function() return pUnit:GetX() end)) or -99
      local y = tonumber(try(function() return pUnit:GetY() end)) or -99
      local ut = try(function() return GameInfo.Units[pUnit:GetType()].UnitType end)
      out[#out + 1] = string.format("%s@(%d,%d)", tostring(ut), x, y)
    end
  end)
  return out
end

local function describe(pid, tag)
  local p = Players[pid]
  local n = tonumber(try(function() return p:GetCities():GetCount() end)) or -1
  local cap = try(function() return tostring(p:GetCities():GetCapitalCity()) end)
  local us = unitList(pid)
  local lt = "?"
  if PlayerConfigurations ~= nil then lt = try(function() return PlayerConfigurations[pid]:GetLeaderTypeName() end) end
  P(string.format("  %s %2d alive=%-5s cities=%d cap=%-5s units=%d leader=%s",
    tag, pid, try(function() return p:IsAlive() end), n, (cap == "nil") and "nil" or "YES",
    #us, tostring(lt)))
end

P("== 当前回合 ==")
P("  Turn = "..try(function() return Game.GetCurrentGameTurn() end))

local ids = PlayerManager.GetAliveMinorIDs()
P("")
P("== 基线：存活城邦 "..#ids.." 个 ==")
for i = 1, #ids do describe(ids[i], "BASE") end

-- 找一个 0 城城邦作为「激活」目标（U6/U7）
local zeroMinor = nil
for i = 1, #ids do
  local n = tonumber(try(function() return Players[ids[i]]:GetCities():GetCount() end)) or 0
  if n == 0 then zeroMinor = ids[i] end
end

P("")
P("========== U2：制造休眠城邦 ==========")
local dormantTarget = nil
for i = #ids, 1, -1 do
  if ids[i] ~= zeroMinor then dormantTarget = ids[i]; break end
end
if dormantTarget == nil then
  P("  (无可用目标)")
else
  P("  目标 = 城邦 "..dormantTarget)
  P("  ① InitUnit(UNIT_SETTLER,-1,-1) -> "..
    try(function() return tostring(UnitManager.InitUnit(dormantTarget, "UNIT_SETTLER", -1, -1)) end))
  local killed = 0
  local ok, pUnits = pcall(function() return Players[dormantTarget]:GetUnits() end)
  if ok and pUnits ~= nil then
    pcall(function()
      for ii, pUnit in pUnits:Members() do
        local x = tonumber(try(function() return pUnit:GetX() end)) or -99
        if x >= 0 then UnitManager.Kill(pUnit, false); killed = killed + 1 end
      end
    end)
  end
  P("  ② 杀掉地图上单位 "..killed.." 个")
  describe(dormantTarget, "DORM")
end

P("")
P("========== U6/U7：给 0 城城邦建城 ==========")
local activatedTarget = nil
if zeroMinor == nil then
  P("  (无 0 城城邦)")
else
  local cityPlots = {}
  for x = 0, 65 do
    for y = 0, 45 do
      local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
      if ok and c ~= nil then cityPlots[#cityPlots + 1] = {x, y} end
    end
  end
  local function far(x, y)
    for _, cp in ipairs(cityPlots) do
      local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
      if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then return false end
    end
    return true
  end
  local spot = nil
  for x = 0, 65 do
    for y = 0, 45 do
      local plot = Map.GetPlot(x, y)
      if plot ~= nil then
        local w = try(function() return plot:IsWater() end)
        local o = try(function() return plot:GetOwner() end)
        if w == "false" and o == "-1" and far(x, y) then spot = {x, y}; break end
      end
    end
    if spot ~= nil then break end
  end
  if spot == nil then
    P("  (找不到合法空地)")
  else
    P(string.format("  目标 = 城邦 %d @(%d,%d)   场上城市数=%d", zeroMinor, spot[1], spot[2], #cityPlots))
    P("  Create -> "..try(function()
      Players[zeroMinor]:GetCities():Create(spot[1], spot[2]); return "called" end))
    P("  建后 cities = "..try(function() return Players[zeroMinor]:GetCities():GetCount() end))
    P("  该格归属   = "..try(function() return Map.GetPlot(spot[1], spot[2]):GetOwner() end))
    P("  城市名     = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    activatedTarget = zeroMinor
    describe(zeroMinor, "ACTV")
  end
end

P("")
P("========== U5：重复城邦（两个城邦共用同一 CivilizationType）==========")
local a, b = nil, nil
for i = 1, #ids do
  if ids[i] ~= dormantTarget and ids[i] ~= activatedTarget then
    if a == nil then a = ids[i] elseif b == nil then b = ids[i] end
  end
  if a ~= nil and b ~= nil then break end
end
if a == nil or b == nil then
  P("  (可用城邦不足)")
else
  P(string.format("  源 = 城邦 %d，目标 = 城邦 %d", a, b))
  local srcLeader = try(function() return PlayerConfigurations[a]:GetLeaderTypeName() end)
  local srcCiv    = try(function() return PlayerConfigurations[a]:GetCivilizationTypeName() end)
  P("  源 leader="..tostring(srcLeader).."  civ="..tostring(srcCiv))
  P("  目标(改前) leader="..try(function() return PlayerConfigurations[b]:GetLeaderTypeName() end)
    .."  civ="..try(function() return PlayerConfigurations[b]:GetCivilizationTypeName() end))
  P("  SetLeaderTypeName       -> "..try(function()
    PlayerConfigurations[b]:SetLeaderTypeName(srcLeader); return "ok" end))
  P("  SetCivilizationTypeName -> "..try(function()
    PlayerConfigurations[b]:SetCivilizationTypeName(srcCiv); return "ok" end))
  P("  目标(改后) leader="..try(function() return PlayerConfigurations[b]:GetLeaderTypeName() end)
    .."  civ="..try(function() return PlayerConfigurations[b]:GetCivilizationTypeName() end))
  P("  ⚠️ 运行时改 PlayerConfigurations 对已创建 civ 对象是否生效 —— 本次即验证点")
end

P("")
P("== 布置后总览 ==")
local ids2 = PlayerManager.GetAliveMinorIDs()
for i = 1, #ids2 do describe(ids2[i], "POST") end
P("")
P(string.format("  MARKERS dormant=%s activated=%s dupA=%s dupB=%s",
  tostring(dormantTarget), tostring(activatedTarget), tostring(a), tostring(b)))
"""
    + EPILOGUE
)

# ---- 24. U2/U5/U6/U7 综合测试：复查 ------------------------------------
PROBES["u567_verify"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1, 60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 回合 ==")
P("  Turn = "..try(function() return Game.GetCurrentGameTurn() end))
P("  LocalPlayer = "..try(function() return Game.GetLocalPlayer() end))

P("")
P("== 全部存活城邦 ==")
local ids = PlayerManager.GetAliveMinorIDs()
P("  存活城邦数 = "..#ids)
for i = 1, #ids do
  local pid = ids[i]
  local p = Players[pid]
  local n = tonumber(try(function() return p:GetCities():GetCount() end)) or 0
  local lt, ct = "?", "?"
  if PlayerConfigurations ~= nil then
    lt = try(function() return PlayerConfigurations[pid]:GetLeaderTypeName() end)
    ct = try(function() return PlayerConfigurations[pid]:GetCivilizationTypeName() end)
  end
  local inh = try(function()
    local li = GameInfo.Leaders[lt]
    return (li ~= nil and li.InheritFrom) or "nil"
  end)
  P(string.format("  城邦 %2d alive=%-5s cities=%d leader=%-34s civ=%-30s 类别=%s",
    pid, try(function() return p:IsAlive() end), n, tostring(lt), tostring(ct), tostring(inh)))
  P(string.format("        CanReceiveInfluence=%s  tokensReceived(0)=%s  suzerain=%s",
    try(function() return p:GetInfluence():CanReceiveInfluence() end),
    try(function() return p:GetInfluence():GetTokensReceived(0) end),
    try(function() return p:GetInfluence():GetSuzerain() end)))
  if n > 0 then
    for x = 0, 65 do
      for y = 0, 45 do
        local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
        if ok and c ~= nil then
          if tonumber(try(function() return c:GetOwner() end)) == pid then
            P(string.format("        city @(%2d,%2d) pop=%-3s name=%s", x, y,
              try(function() return c:GetPopulation() end),
              try(function() return c:GetName() end)))
          end
        end
      end
    end
  end
end

P("")
P("== 主文明城市数 ==")
local mids = PlayerManager.GetAliveMajorIDs()
for i = 1, #mids do
  P(string.format("  major %2d cities=%s", mids[i],
    try(function() return Players[mids[i]]:GetCities():GetCount() end)))
end

P("")
P("== 本地玩家使者侧 ==")
P("  GetTokensToGive = "..try(function() return Players[0]:GetInfluence():GetTokensToGive() end))
"""
    + EPILOGUE
)


# ---- 25. 运行时配置库：MapSizes 真实值（DebugConfiguration.sqlite 是缓存快照，不可信）----
PROBES["mapsizes"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 运行时 MapSizes（DB.ConfigurationQuery，权威值）==")
local tRows = try(function()
  return DB.ConfigurationQuery("SELECT MapSizeType, Domain, DefaultCityStates, MaxCityStates, MinCityStates FROM MapSizes ORDER BY MapSizeType, Domain")
end)
if type(tRows) ~= "table" then
  P("  查询失败: " .. tostring(tRows))
else
  for _, row in ipairs(tRows) do
    P(string.format("  %-18s %-22s def=%-4s max=%-4s min=%s",
      tostring(row.MapSizeType), tostring(row.Domain),
      tostring(row.DefaultCityStates), tostring(row.MaxCityStates), tostring(row.MinCityStates)))
  end
  P("  总行数 = " .. tostring(#tRows))
end

P("")
P("== 本局实际城邦数 ==")
P("  GetAliveMinorsCount = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  MAX_PLAYERS         = "..try(function() return GameDefines.MAX_PLAYERS end))
P("  MAX_MAJOR_CIVS      = "..try(function() return GameDefines.MAX_MAJOR_CIVS end))

P("")
P("== 当前 CityStates 池（按 Domain 计数）==")
local tPool = try(function()
  return DB.ConfigurationQuery("SELECT Domain, COUNT(*) AS N FROM CityStates GROUP BY Domain")
end)
if type(tPool) == "table" then
  for _, row in ipairs(tPool) do
    P(string.format("  %-24s %s 条", tostring(row.Domain), tostring(row.N)))
  end
end
"""
    + EPILOGUE
)


# ---- 26. ⭐ 决定性探测：运行时能否「新建玩家 / 改文明身份」----------------
#   WorldBuilderPlayerEditor.lua:1231/1240/1258 暴露了引擎里的
#     WorldBuilder.PlayerManager():AddPlayer(bIsAI)
#     WorldBuilder.PlayerManager():SetPlayerLeader(index, leader, civ, civLevel)
#   若这些在【普通对局】里可用，就能给任意城邦文明创建玩家槽
#   → 玩家可选范围从"本局已有的 N 个"扩展到【全部 48 个城邦定义】。
PROBES["wbprobe"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. WorldBuilder 全局表是否存在于普通对局 ==")
P("  type(WorldBuilder) = "..try(function() return type(WorldBuilder) end))

P("")
P("== 2. WorldBuilder.PlayerManager() 是否可调用 ==")
local pm = nil
P("  WorldBuilder.PlayerManager() -> "..try(function()
  pm = WorldBuilder.PlayerManager(); return type(pm)
end))

if pm ~= nil then
  P("")
  P("== 3. 它的方法表 ==")
  local n = 0
  for k, v in pairs(pm) do
    if type(v) == "function" then
      n = n + 1
      if n <= 40 then P("    "..tostring(k)) end
    end
  end
  P("  方法总数 = "..n)

  P("")
  P("== 4. 关键方法是否存在 ==")
  for _, name in ipairs({"AddPlayer","SetPlayerLeader","UninitializePlayer",
                         "GetPlayerConfig","GetSlotStatus","IsPlayerInitialized"}) do
    P("    "..name.." = "..try(function() return type(pm[name]) end))
  end
end

P("")
P("== 5. 非 WorldBuilder 的 PlayerManager 是否有同类方法 ==")
for _, name in ipairs({"AddPlayer","SetPlayerLeader","CreatePlayer","SetPlayerType"}) do
  P("  PlayerManager."..name.." = "..try(function() return type(PlayerManager[name]) end))
end

P("")
P("== 6. PlayerConfigurations 的 setter 在这个上下文里存在吗 ==")
local tIDs = try(function() return PlayerManager.GetAliveMinorIDs() end)
local iFirst = (type(tIDs) == "table" and #tIDs > 0) and tIDs[1] or 0
P("  取样城邦 playerID = "..tostring(iFirst))
for _, name in ipairs({"SetLeaderTypeName","SetCivilizationTypeName",
                       "GetLeaderTypeName","GetCivilizationTypeName"}) do
  P("  PlayerConfigurations[id]."..name.." = "..
    try(function() return type(PlayerConfigurations[iFirst][name]) end))
end

P("")
P("== 7. 玩家槽总览 ==")
local iObj, iAlive = 0, 0
for i = 0, 63 do
  local ok, p = pcall(function() return Players[i] end)
  if ok and p ~= nil then
    iObj = iObj + 1
    local a = try(function() return p:IsAlive() end)
    if a == "true" then iAlive = iAlive + 1 end
  end
end
P("  有 Player 对象的槽 = "..iObj.." / 64")
P("  存活 = "..iAlive)
P("  GetAliveMinorsCount = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  GetAliveMajorsCount = "..try(function() return PlayerManager.GetAliveMajorsCount() end))

P("")
P("== 8. 空闲槽长什么样（前 3 个非存活槽）==")
local nShown = 0
for i = 0, 63 do
  if nShown < 3 then
    local ok, p = pcall(function() return Players[i] end)
    if ok and p ~= nil then
      local a = try(function() return p:IsAlive() end)
      if a ~= "true" then
        nShown = nShown + 1
        P(string.format("  槽 %d: IsAlive=%s IsMajor=%s IsBarbarian=%s leader=%s civ=%s",
          i, a,
          try(function() return p:IsMajor() end),
          try(function() return p:IsBarbarian() end),
          try(function() return PlayerConfigurations[i]:GetLeaderTypeName() end),
          try(function() return PlayerConfigurations[i]:GetCivilizationTypeName() end)))
      end
    end
  end
end
"""
    + EPILOGUE
)


# ---- 27. ⭐ WorldBuilder.PlayerManager 完整枚举 + 64 槽全表（只读）--------
PROBES["wbslots"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

P("== 1. 通过元表枚举 PlayerManager 的完整方法表 ==")
local mt = getmetatable(pm)
P("  getmetatable(pm) = "..try(function() return type(mt) end))
if mt ~= nil then
  local idx = mt.__index
  P("  __index = "..try(function() return type(idx) end))
  if type(idx) == "table" then
    local n = 0
    local names = {}
    for k, v in pairs(idx) do
      if type(v) == "function" then n = n + 1; names[#names+1] = tostring(k) end
    end
    table.sort(names)
    P("  方法总数 = "..n)
    for _, s in ipairs(names) do P("    "..s) end
  elseif type(idx) == "function" then
    P("  （__index 是函数，无法枚举；改用逐个试名字）")
  end
end

P("")
P("== 2. 64 个槽全表 ==")
P("  槽 | 存活 | Major | Barb | 文明 | 领袖 | 槽状态")
local iAssigned, iAliveMinor = 0, 0
local tCivSeen = {}
for i = 0, 63 do
  local ok, p = pcall(function() return Players[i] end)
  if ok and p ~= nil then
    local sCiv = try(function() return PlayerConfigurations[i]:GetCivilizationTypeName() end)
    local sLdr = try(function() return PlayerConfigurations[i]:GetLeaderTypeName() end)
    local sAlive = try(function() return p:IsAlive() end)
    local sMajor = try(function() return p:IsMajor() end)
    local sBarb  = try(function() return p:IsBarbarian() end)
    local sStat  = try(function() return tostring(pm:GetSlotStatus(i)) end)
    if sCiv ~= "nil" and sCiv ~= "" then iAssigned = iAssigned + 1; tCivSeen[sCiv] = true end
    if sAlive == "true" and sMajor == "false" and sBarb == "false" then iAliveMinor = iAliveMinor + 1 end
    P(string.format("  %2d | %-5s | %-5s | %-5s | %-42s | %-38s | %s",
      i, sAlive, sMajor, sBarb, sCiv, sLdr, sStat))
  end
end
P("")
P("  已分配文明的槽数 = "..iAssigned.." / 64")
P("  存活的 minor 数   = "..iAliveMinor)
local iDistinct = 0
for _ in pairs(tCivSeen) do iDistinct = iDistinct + 1 end
P("  出现过的不同文明数 = "..iDistinct)

P("")
P("== 3. 与 CityStates 池对比：本局覆盖了多少 ==")
local sRuleset = try(function() return GameConfiguration.GetValue("RULESET") end)
local sDomain = "Expansion2CityStates"
if sRuleset == "RULESET_EXPANSION_1" then sDomain = "Expansion1CityStates"
elseif sRuleset ~= "RULESET_EXPANSION_2" then sDomain = "StandardCityStates" end
P("  RULESET="..sRuleset.."  Domain="..sDomain)
local tPool = try(function()
  return DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates WHERE Domain = ?", sDomain)
end)
if type(tPool) == "table" then
  P("  池内城邦定义数 = "..#tPool)
  local iCovered, iMissing = 0, 0
  local tMissing = {}
  for _, row in ipairs(tPool) do
    if tCivSeen[row.CivilizationType] then iCovered = iCovered + 1
    else iMissing = iMissing + 1; tMissing[#tMissing+1] = row.CivilizationType end
  end
  P("  本局槽位已覆盖 = "..iCovered)
  P("  池里有、本局没有 = "..iMissing)
  if iMissing > 0 then
    P("  （未覆盖的前 15 个）")
    for i = 1, math.min(15, #tMissing) do P("    "..tMissing[i]) end
  end
end
"""
    + EPILOGUE
)


# ---- 28. ⭐ SlotStatus 枚举值 + 槽状态分布（只读）------------------------
PROBES["slotenum"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. SlotStatus 枚举值 ==")
P("  type(SlotStatus) = "..try(function() return type(SlotStatus) end))
if type(SlotStatus) == "table" then
  local t = {}
  for k, v in pairs(SlotStatus) do t[#t+1] = { k = tostring(k), v = v } end
  table.sort(t, function(a,b) return tostring(a.v) < tostring(b.v) end)
  for _, e in ipairs(t) do
    P(string.format("    %-16s = %s", e.k, tostring(e.v)))
  end
end

P("")
P("== 2. 反查：每个数值对应哪个名字 ==")
local tRev = {}
if type(SlotStatus) == "table" then
  for k, v in pairs(SlotStatus) do
    if type(v) == "number" then tRev[v] = tostring(k) end
  end
end
for i = 0, 8 do
  if tRev[i] ~= nil then P("    "..i.." -> "..tRev[i]) end
end

P("")
P("== 3. 64 槽的状态分布 ==")
local pm = WorldBuilder.PlayerManager();
local tCount = {}
local tByStatus = {}
for i = 0, 63 do
  local st = try(function() return pm:GetSlotStatus(i) end)
  local n = tonumber(st)
  if n ~= nil then
    tCount[n] = (tCount[n] or 0) + 1
    tByStatus[n] = tByStatus[n] or {}
    table.insert(tByStatus[n], i)
  end
end
for n = 0, 8 do
  if tCount[n] ~= nil then
    local ids = tByStatus[n]
    local sIds = ""
    for i = 1, math.min(12, #ids) do sIds = sIds .. tostring(ids[i]) .. " " end
    if #ids > 12 then sIds = sIds .. "..." end
    P(string.format("    状态 %s (%s) : %d 个槽   [%s]",
      tostring(n), tostring(tRev[n] or "?"), tCount[n], sIds))
  end
end

P("")
P("== 4. 取一个状态=5 的槽，看它是否已初始化 ==")
local iTest = nil
for i = 0, 63 do
  if tonumber(try(function() return pm:GetSlotStatus(i) end)) == 5 then iTest = i; break end
end
if iTest ~= nil then
  P("  取样槽 = "..iTest)
  P("    IsPlayerInitialized = "..try(function() return tostring(pm:IsPlayerInitialized(iTest)) end))
  P("    GetPlayerConfig      = "..try(function() return type(pm:GetPlayerConfig(iTest)) end))
  P("    Players[槽] 是否存在  = "..try(function() return tostring(Players[iTest] ~= nil) end))
  P("    IsAlive              = "..try(function() return tostring(Players[iTest]:IsAlive()) end))
  P("    GetCities():GetCount = "..try(function() return Players[iTest]:GetCities():GetCount() end))
  P("    GetUnits() 单位数     = "..try(function()
    local n = 0
    for _ in Players[iTest]:GetUnits():Members() do n = n + 1 end
    return n
  end))
end

P("")
P("== 5. GetMaxPlayers ==")
P("  "..try(function() return pm:GetMaxPlayers() end))
"""
    + EPILOGUE
)


# ---- 29. ⭐⭐ 激活预分配的城邦槽（写操作！用户已授权）--------------------
PROBES["initplayer"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function snapshot(i, tag)
  P(string.format("  [%s] 槽 %d", tag, i))
  P("    GetSlotStatus        = "..try(function() return tostring(pm:GetSlotStatus(i)) end))
  P("    IsPlayerInitialized  = "..try(function() return tostring(pm:IsPlayerInitialized(i)) end))
  P("    Players[槽] 存在      = "..try(function() return tostring(Players[i] ~= nil) end))
  P("    IsAlive              = "..try(function() return tostring(Players[i]:IsAlive()) end))
  P("    IsMajor              = "..try(function() return tostring(Players[i]:IsMajor()) end))
  P("    civ                  = "..try(function() return PlayerConfigurations[i]:GetCivilizationTypeName() end))
  P("    GetCities()          = "..try(function()
    local c = Players[i]:GetCities(); return type(c)
  end))
  P("    GetCities():GetCount = "..try(function() return Players[i]:GetCities():GetCount() end))
  P("    GetUnits() 单位数     = "..try(function()
    local n = 0
    for _ in Players[i]:GetUnits():Members() do n = n + 1 end
    return n
  end))
end

local TARGET = 15;

P("================ 步骤 0：激活前 ================")
snapshot(TARGET, "BEFORE")

P("")
P("================ 步骤 1：InitializePlayer("..TARGET..") ================")
P("  调用 -> "..try(function()
  local r = pm:InitializePlayer(TARGET);
  return "returned "..tostring(r)
end))

P("")
P("================ 步骤 2：激活后 ================")
snapshot(TARGET, "AFTER")

P("")
P("================ 步骤 3：全局影响检查 ================")
P("  GetAliveMinorsCount = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  GetAliveMajorsCount = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  回合                 = "..try(function() return Game.GetCurrentGameTurn() end))
P("  本地玩家             = "..try(function() return Game.GetLocalPlayer() end))
"""
    + EPILOGUE
)


# ---- 30. ⭐⭐ 试其余激活路径：SetPlayerSlotStatus / AddPlayer（写操作）----
PROBES["activate2"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function snap(i, tag)
  P(string.format("  [%s] 槽 %d : status=%s init=%s alive=%s cities=%s units=%s",
    tag, i,
    try(function() return tostring(pm:GetSlotStatus(i)) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end),
    try(function()
      local n = 0
      for _ in Players[i]:GetUnits():Members() do n = n + 1 end
      return n
    end)))
end

local TARGET = 15;

P("================ A. SetPlayerSlotStatus(15, SS_COMPUTER=1) ================")
snap(TARGET, "BEFORE")
P("  调用 -> "..try(function()
  local r = pm:SetPlayerSlotStatus(TARGET, SlotStatus.SS_COMPUTER);
  return "returned "..tostring(r)
end))
snap(TARGET, "AFTER-1")

P("")
P("  再试 SetPlayerSlotStatus(15, 3) [SS_TAKEN]")
P("  调用 -> "..try(function()
  local r = pm:SetPlayerSlotStatus(TARGET, SlotStatus.SS_TAKEN);
  return "returned "..tostring(r)
end))
snap(TARGET, "AFTER-3")

P("")
P("================ B. 试试 AddPlayer ================")
P("  当前存活 minor = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AddPlayer(true) -> "..try(function()
  local r = pm:AddPlayer(true);
  return "returned "..tostring(r)
end))
P("  之后存活 minor = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  之后存活 major = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  GetMaxPlayers  = "..try(function() return pm:GetMaxPlayers() end))

P("")
P("  再扫一遍 15..20 和 54..56 的状态：")
for _, i in ipairs({15,16,17,18,19,20,54,55,56}) do
  snap(i, "SCAN")
end

P("")
P("================ C. 是否有「模式」标志 ================")
for _, name in ipairs({"IsWorldBuilderMode","IsActive","IsEnabled","GetMode"}) do
  P("  pm."..name.." = "..try(function() return type(pm[name]) end))
end
P("  Game:GetProperty('BBM_RESPAWN') = "..try(function() return tostring(Game:GetProperty('BBM_RESPAWN')) end))
"""
    + EPILOGUE
)


# ---- 31. ⭐⭐⭐ 给新玩家指定城邦文明 + 建城（写操作，用户已授权）----------
PROBES["setleader"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function info(i, tag)
  P(string.format("  [%s] 槽 %d: status=%s init=%s alive=%s major=%s civ=%s leader=%s cities=%s",
    tag, i,
    try(function() return tostring(pm:GetSlotStatus(i)) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(Players[i]:IsMajor()) end),
    try(function() return PlayerConfigurations[i]:GetCivilizationTypeName() end),
    try(function() return PlayerConfigurations[i]:GetLeaderTypeName() end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end)))
end

P("================ 0. 刚才 AddPlayer 创建的槽 54 ================")
info(54, "NOW")

P("")
P("================ 1. 试 SetPlayerLeader 的三种参数形式 ================")
-- 目标城邦：ARMAGH（预分配在槽 15 的那个）
local tForms = {
  { "leader,civ,level(number 1)", "LEADER_MINOR_CIV_ARMAGH", "CIVILIZATION_ARMAGH", 1 },
  { "leader,civ,nil",            "LEADER_MINOR_CIV_ARMAGH", "CIVILIZATION_ARMAGH", nil },
  { "leader,civ,string",         "LEADER_MINOR_CIV_ARMAGH", "CIVILIZATION_ARMAGH", "CIV_LEVEL_MINOR" },
}
for _, f in ipairs(tForms) do
  P("")
  P("  --- 形式: "..f[1].." ---")
  P("    调用 -> "..try(function()
    local r
    if f[4] == nil then
      r = pm:SetPlayerLeader(54, f[2], f[3])
    else
      r = pm:SetPlayerLeader(54, f[2], f[3], f[4])
    end
    return "returned "..tostring(r)
  end))
  info(54, "AFTER")
end

P("")
P("================ 2. 直接用预分配槽的思路：AddPlayer 会不会自动带文明 ================")
P("  再 AddPlayer(true) 一次，看新槽是否自带 civ")
local iNew = try(function() return tostring(pm:AddPlayer(true)) end)
P("  返回 = "..tostring(iNew))
local nNew = tonumber(iNew)
if nNew ~= nil then info(nNew, "NEW") end

P("")
P("================ 3. 全局状态 ================")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  Turn        = "..try(function() return Game.GetCurrentGameTurn() end))
"""
    + EPILOGUE
)


# ---- 32. ⭐⭐⭐ 终极验证：为 AddPlayer+SetPlayerLeader 造出的城邦建城 -------
PROBES["wbcreate"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function info(i, tag)
  P(string.format("  [%s] 槽 %d: alive=%s major=%s civ=%s cities=%s",
    tag, i,
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(Players[i]:IsMajor()) end),
    try(function() return PlayerConfigurations[i]:GetCivilizationTypeName() end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end)))
end

local TARGET = 54;   -- 上一步造出的 ARMAGH 槽

P("================ 0. 现状 ================")
info(TARGET, "BEFORE")
P("  场上城市总数（建前）:")
local tCitiesBefore = {}
for x = 0, 80 do
  for y = 0, 60 do
    local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
    if ok and c ~= nil then tCitiesBefore[#tCitiesBefore+1] = {x, y} end
  end
end
P("    "..#tCitiesBefore.." 座")

P("")
P("================ 1. 找一块合法空地（离所有城市 >= 4）================")
local function farEnough(x, y)
  for _, cp in ipairs(tCitiesBefore) do
    local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
    if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then return false end
  end
  return true
end

local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local p = Map.GetPlot(x, y)
    if p ~= nil then
      local w = try(function() return p:IsWater() end)
      local o = try(function() return p:GetOwner() end)
      if w == "false" and o == "-1" and farEnough(x, y) then spot = {x, y}; break end
    end
  end
  if spot ~= nil then break end
end

if spot == nil then
  P("  找不到合法空地")
else
  P(string.format("  选定 (%d, %d)", spot[1], spot[2]))

  P("")
  P("================ 2. Create() ================")
  P("  调用 -> "..try(function()
    Players[TARGET]:GetCities():Create(spot[1], spot[2]);
    return "called"
  end))
  info(TARGET, "AFTER")

  P("")
  P("================ 3. 复查（是否真建出来了）================")
  P("  该格归属     = "..try(function() return Map.GetPlot(spot[1], spot[2]):GetOwner() end))
  P("  城市名       = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
  P("  人口         = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetPopulation() end))
  P("  CanReceiveInfluence = "..try(function()
    return tostring(Players[TARGET]:GetInfluence():CanReceiveInfluence())
  end))

  P("")
  P("================ 4. 原生性检查 ================")
  P("  LeaderTypeName = "..try(function() return PlayerConfigurations[TARGET]:GetLeaderTypeName() end))
  P("  CivTypeName    = "..try(function() return PlayerConfigurations[TARGET]:GetCivilizationTypeName() end))
  P("  城邦类别       = "..try(function()
    local lt = PlayerConfigurations[TARGET]:GetLeaderTypeName()
    return GameInfo.Leaders[lt].InheritFrom
  end))
end

P("")
P("================ 5. 全局 ================")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  Turn        = "..try(function() return Game.GetCurrentGameTurn() end))
"""
    + EPILOGUE
)


# ---- 33. ⭐⭐ 补全初始化：InitializePlayer 放在 SetPlayerLeader 之后 ------
PROBES["wbfix"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function info(i, tag)
  P(string.format("  [%s] 槽 %d: alive=%s init=%s civ=%s cities=%s canInfluence=%s",
    tag, i,
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return PlayerConfigurations[i]:GetCivilizationTypeName() end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end),
    try(function() return tostring(Players[i]:GetInfluence():CanReceiveInfluence()) end)))
end

P("================ 0. 现状：上一步造出的 ARMAGH 槽 54 ================")
info(54, "NOW")
P("  本地玩家能否给它派使者 = "..try(function()
  return tostring(Players[0]:GetInfluence():CanGiveTokensToPlayer(54))
end))

P("")
P("================ 1. 走完整流程再造一个（这次加 InitializePlayer）================")
local iNew = tonumber(try(function() return tostring(pm:AddPlayer(true)) end))
P("  AddPlayer -> "..tostring(iNew))
if iNew ~= nil then
  info(iNew, "STEP1")

  P("")
  P("  SetPlayerLeader("..iNew..", KANDY) -> "..try(function()
    pm:SetPlayerLeader(iNew, "LEADER_MINOR_CIV_KANDY", "CIVILIZATION_KANDY", 1);
    return "called"
  end))
  info(iNew, "STEP2")

  P("")
  P("  InitializePlayer("..iNew..") -> "..try(function()
    return "returned "..tostring(pm:InitializePlayer(iNew))
  end))
  info(iNew, "STEP3")

  P("")
  P("  再次 SetPlayerLeader（看是否会二次初始化）-> "..try(function()
    pm:SetPlayerLeader(iNew, "LEADER_MINOR_CIV_KANDY", "CIVILIZATION_KANDY", 1);
    return "called"
  end))
  info(iNew, "STEP4")

  P("")
  P("  给新槽建城：")
  local tCities = {}
  for x = 0, 80 do
    for y = 0, 60 do
      local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
      if ok and c ~= nil then tCities[#tCities+1] = {x, y} end
    end
  end
  local spot = nil
  for x = 0, 80 do
    for y = 0, 60 do
      local p = Map.GetPlot(x, y)
      if p ~= nil then
        local w = try(function() return p:IsWater() end)
        local o = try(function() return p:GetOwner() end)
        if w == "false" and o == "-1" then
          local ok2 = true
          for _, cp in ipairs(tCities) do
            local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
            if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then ok2 = false; break end
          end
          if ok2 then spot = {x, y}; break end
        end
      end
    end
    if spot ~= nil then break end
  end
  if spot ~= nil then
    P(string.format("    建在 (%d,%d)", spot[1], spot[2]))
    try(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
    info(iNew, "STEP5")
    P("    城市名 = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("    类别   = "..try(function()
      local lt = PlayerConfigurations[iNew]:GetLeaderTypeName()
      return GameInfo.Leaders[lt].InheritFrom
    end))
  else
    P("    找不到空地")
  end
end

P("")
P("================ 2. 对照：原有城邦（槽 6）为什么是 true ================")
info(6, "ORIG")
P("  本地玩家能否给它派使者 = "..try(function()
  return tostring(Players[0]:GetInfluence():CanGiveTokensToPlayer(6))
end))
P("  是否已遇见(槽6) = "..try(function()
  return tostring(Players[0]:GetDiplomacy():HasMet(6))
end))
P("  是否已遇见(槽54) = "..try(function()
  return tostring(Players[0]:GetDiplomacy():HasMet(54))
end))
"""
    + EPILOGUE
)


# ---- 34. ⭐⭐⭐ 激活【预分配城邦槽】(15-53) 而非空槽 ----------------------
PROBES["wbpre"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,55)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function info(i, tag)
  P(string.format("  [%s] 槽 %2d: alive=%-5s init=%-5s status=%s civ=%-28s cities=%s canInf=%s",
    tag, i,
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return tostring(pm:GetSlotStatus(i)) end),
    try(function() return tostring(PlayerConfigurations[i]:GetCivilizationTypeName()) end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end),
    try(function() return tostring(Players[i]:GetInfluence():CanReceiveInfluence()) end)))
end

P("================ 对照组 ================")
info(6,  "原有城邦")
info(54, "AddPlayer造的")

P("")
P("================ 激活预分配城邦槽 16 (MEXICO_CITY) ================")
info(16, "BEFORE")
P("  SetPlayerLeader(16, ...) -> "..try(function()
  pm:SetPlayerLeader(16, "LEADER_MINOR_CIV_MEXICO_CITY", "CIVILIZATION_MEXICO_CITY", 1);
  return "called"
end))
info(16, "AFTER")

P("")
P("================ 激活预分配城邦槽 17 (CAHOKIA) ================")
info(17, "BEFORE")
P("  SetPlayerLeader(17, ...) -> "..try(function()
  pm:SetPlayerLeader(17, "LEADER_MINOR_CIV_CAHOKIA", "CIVILIZATION_CAHOKIA", 1);
  return "called"
end))
info(17, "AFTER")

P("")
P("================ 给槽 16 建城 ================")
local tCities = {}
for x = 0, 80 do
  for y = 0, 60 do
    local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
    if ok and c ~= nil then tCities[#tCities+1] = {x, y} end
  end
end
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local p = Map.GetPlot(x, y)
    if p ~= nil then
      local w = try(function() return p:IsWater() end)
      local o = try(function() return p:GetOwner() end)
      if w == "false" and o == "-1" then
        local ok2 = true
        for _, cp in ipairs(tCities) do
          local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
          if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then ok2 = false; break end
        end
        if ok2 then spot = {x, y}; break end
      end
    end
  end
  if spot ~= nil then break end
end
if spot ~= nil then
  P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
  try(function() Players[16]:GetCities():Create(spot[1], spot[2]) end)
  info(16, "AFTER-CITY")
  P("  城市名 = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
else
  P("  找不到空地")
end

P("")
P("================ 汇总 ================")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
"""
    + EPILOGUE
)


# ---- 35. ⭐⭐⭐ 对比两个玩家的 PlayerInfluence 对象，找 CanReceiveInfluence 的差异 ----
PROBES["influence"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,55)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

-- 递归列出对象的所有可读字段/方法（含元表 __index）
local function dump(obj, label)
  P("  ---- "..label.." ----")
  local seen = {}
  local function scan(t, tag)
    if type(t) ~= "table" then return end
    local names = {}
    for k, v in pairs(t) do
      if type(k) == "string" then names[#names+1] = k end
    end
    table.sort(names)
    for _, k in ipairs(names) do
      if not seen[k] then
        seen[k] = true
        local v = t[k]
        local tv = type(v)
        if tv == "function" then
          P(string.format("    %-34s : function", k))
        else
          P(string.format("    %-34s : %-8s = %s", k, tv, tostring(v)))
        end
      end
    end
  end
  scan(obj, label)
  local mt = getmetatable(obj)
  if mt ~= nil and type(mt.__index) == "table" then scan(mt.__index, label..".__index") end
end

local iOrig = 6;    -- 原有城邦 KANDY
local iNew  = 56;   -- AddPlayer 造的 KANDY

P("================ 1. 两个玩家的影响力对象对比 ================")
P("  原有城邦 槽 "..iOrig.." CanReceiveInfluence = "..
  try(function() return tostring(Players[iOrig]:GetInfluence():CanReceiveInfluence()) end))
P("  新建城邦 槽 "..iNew.."  CanReceiveInfluence = "..
  try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
P("")

dump(Players[iOrig]:GetInfluence(), "原有城邦 Influence")
P("")
dump(Players[iNew]:GetInfluence(),  "新建城邦 Influence")

P("")
P("================ 2. 两个玩家对象的差异 ================")
P("  原有城邦 槽 "..iOrig..":")
P("    IsAlive="..try(function() return tostring(Players[iOrig]:IsAlive()) end))
P("    IsMajor="..try(function() return tostring(Players[iOrig]:IsMajor()) end))
P("    IsBarbarian="..try(function() return tostring(Players[iOrig]:IsBarbarian()) end))
P("    IsHuman="..try(function() return tostring(Players[iOrig]:IsHuman()) end))
P("    GetTeam="..try(function() return tostring(Players[iOrig]:GetTeam()) end))
P("    GetEra="..try(function() return tostring(Players[iOrig]:GetEra()) end))
P("    GetScore="..try(function() return tostring(Players[iOrig]:GetScore()) end))
P("    GetTreasury金币="..try(function() return tostring(Players[iOrig]:GetTreasury():GetGoldBalance()) end))
P("  新建城邦 槽 "..iNew..":")
P("    IsAlive="..try(function() return tostring(Players[iNew]:IsAlive()) end))
P("    IsMajor="..try(function() return tostring(Players[iNew]:IsMajor()) end))
P("    IsBarbarian="..try(function() return tostring(Players[iNew]:IsBarbarian()) end))
P("    IsHuman="..try(function() return tostring(Players[iNew]:IsHuman()) end))
P("    GetTeam="..try(function() return tostring(Players[iNew]:GetTeam()) end))
P("    GetEra="..try(function() return tostring(Players[iNew]:GetEra()) end))
P("    GetScore="..try(function() return tostring(Players[iNew]:GetScore()) end))
P("    GetTreasury金币="..try(function() return tostring(Players[iNew]:GetTreasury():GetGoldBalance()) end))

P("")
P("================ 3. 试补全：SetRandomMinorStartingPosition ================")
P("  对槽 "..iNew.." 调用 -> "..try(function()
  local r = WorldBuilder.PlayerManager():SetRandomMinorStartingPosition(iNew);
  return "returned "..tostring(r)
end))
P("  之后 CanReceiveInfluence = "..
  try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
"""
    + EPILOGUE
)


# ---- 36. ⭐⭐ 推进回合后，新建城邦是否被引擎补全 ---------------------------
PROBES["wbturn"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function check(tag)
  P("  ["..tag.."]")
  for _, i in ipairs({6, 54, 56}) do
    P(string.format("    槽 %2d: alive=%-5s team=%-4s treasury=%-10s canInf=%-5s cities=%s",
      i,
      try(function() return tostring(Players[i]:IsAlive()) end),
      try(function() return tostring(Players[i]:GetTeam()) end),
      try(function() return tostring(Players[i]:GetTreasury():GetGoldBalance()) end),
      try(function() return tostring(Players[i]:GetInfluence():CanReceiveInfluence()) end),
      try(function() return tostring(Players[i]:GetCities():GetCount()) end)))
  end
end

P("================ 推进前 ================")
P("  回合 = "..try(function() return Game.GetCurrentGameTurn() end))
check("BEFORE")

P("")
P("================ 推进 3 回合（AutoplayManager 四调用）================")
P("  SetTurns(3) / SetReturnAsPlayer(0) / SetObserveAsPlayer(0) / SetActive(true)")
try(function() AutoplayManager.SetTurns(3) end)
try(function() AutoplayManager.SetReturnAsPlayer(0) end)
try(function() AutoplayManager.SetObserveAsPlayer(0) end)
try(function() AutoplayManager.SetActive(true) end)
P("  已发起（回合将在后台推进，约 1~2 分钟）")
"""
    + EPILOGUE
)


# ---- 37. 推进后复查 -------------------------------------------------------
PROBES["wbturn2"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("================ 推进后 ================")
P("  回合 = "..try(function() return Game.GetCurrentGameTurn() end))
for _, i in ipairs({6, 54, 56}) do
  P(string.format("    槽 %2d: alive=%-5s team=%-4s treasury=%-10s canInf=%-5s cities=%s",
    i,
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(Players[i]:GetTeam()) end),
    try(function() return tostring(Players[i]:GetTreasury():GetGoldBalance()) end),
    try(function() return tostring(Players[i]:GetInfluence():CanReceiveInfluence()) end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end)))
end

P("")
P("  本地玩家能否给槽 56 派使者 = "..try(function()
  return tostring(Players[0]:GetInfluence():CanGiveTokensToPlayer(56))
end))
P("  本地玩家能否给槽 6 派使者  = "..try(function()
  return tostring(Players[0]:GetInfluence():CanGiveTokensToPlayer(6))
end))
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
"""
    + EPILOGUE
)


# ---- 38. ⭐⭐⭐ PlayerConfigurations 完整方法表 + 新旧玩家全面对比 ----------
PROBES["pconfig"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function dumpAll(obj, label)
  P("  ---- "..label.." ----")
  local seen = {}
  local function scan(t)
    if type(t) ~= "table" then return end
    local names = {}
    for k, _ in pairs(t) do if type(k) == "string" then names[#names+1] = k end end
    table.sort(names)
    for _, k in ipairs(names) do
      if not seen[k] then
        seen[k] = true
        local v = t[k]
        if type(v) == "function" then
          P(string.format("    %-36s : function", k))
        elseif type(v) ~= "table" then
          P(string.format("    %-36s : %-8s = %s", k, type(v), tostring(v)))
        end
      end
    end
  end
  scan(obj)
  local mt = getmetatable(obj)
  if mt ~= nil and type(mt.__index) == "table" then scan(mt.__index) end
end

local iOrig = 6;
local iNew  = 56;

P("================ 1. PlayerConfigurations 完整方法表 ================")
dumpAll(PlayerConfigurations[iOrig], "PlayerConfigurations[6] 原有城邦")

P("")
P("================ 2. 两个玩家的 PlayerConfigurations 值对比 ================")
local tKeys = {
  "GetSlotStatus","GetLeaderTypeName","GetCivilizationTypeName","GetPlayerType",
  "IsAlive","IsHuman","IsMajor","IsMinor","GetTeam","GetHandicapType",
  "GetDifficultyType","GetPrimaryColor","GetSecondaryColor","GetArtStyleType",
  "GetCivilizationLevelTypeName","GetName","GetPlayerName",
}
for _, fn in ipairs(tKeys) do
  local a = try(function() return tostring(PlayerConfigurations[iOrig][fn]()) end)
  local b = try(function() return tostring(PlayerConfigurations[iNew][fn]()) end)
  local mark = (a == b) and "  " or "≠ "
  P(string.format("  %s %-30s 原有=%-28s 新建=%s", mark, fn, a, b))
end

P("")
P("================ 3. 两个玩家对象的其他子系统对比 ================")
local tSub = { "GetTreasury","GetInfluence","GetDiplomacy","GetTechs","GetCulture",
               "GetResources","GetStats","GetEra","GetScore","GetProperty" }
for _, fn in ipairs(tSub) do
  local a = try(function() return type(Players[iOrig][fn]) end)
  local b = try(function() return type(Players[iNew][fn]) end)
  local mark = (a == b) and "  " or "≠ "
  P(string.format("  %s Players[x]:%-16s 原有=%-10s 新建=%s", mark, fn, a, b))
end
P("")
P("  原有城邦 GetProperty 测试:")
P("    Game:GetProperty = "..try(function() return tostring(Game:GetProperty("BBM_RESPAWN")) end))
P("    槽6:GetProperty('X') = "..try(function() return tostring(Players[iOrig]:GetProperty("X")) end))
P("    槽56:GetProperty('X') = "..try(function() return tostring(Players[iNew]:GetProperty("X")) end))

P("")
P("================ 4. 试补全手段 ================")
P("  -- 4a. SetPlayerEra / SetPlayerGold 后再看 --")
P("    SetPlayerGold(56, 100) -> "..try(function()
  return "returned "..tostring(WorldBuilder.PlayerManager():SetPlayerGold(56, 100))
end))
P("    之后 treasury = "..try(function() return tostring(Players[iNew]:GetTreasury():GetGoldBalance()) end))
P("    之后 canInf  = "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))

P("")
P("  -- 4b. 有没有 Player:SetAlive / SetTeam 之类 --")
for _, fn in ipairs({"SetAlive","SetTeam","SetPlayerType","SetMajor","SetMinor","SetColor"}) do
  P("    Player."..fn.." = "..try(function() return type(Players[iNew][fn]) end))
end
"""
    + EPILOGUE
)


# ---- 39. ⭐⭐⭐ 最终验证：带文明等级的动态创建 + T-79 预分配槽激活 ----------
PROBES["verify_cs"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,55)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function info(i, tag)
  P(string.format("  [%s] 槽 %2d: alive=%-5s init=%-5s lvl=%-32s canInf=%-5s cities=%s",
    tag, i,
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return tostring(PlayerConfigurations[i]:GetCivilizationLevelTypeName()) end),
    try(function() return tostring(Players[i]:GetInfluence():CanReceiveInfluence()) end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end)))
end

P("############ 对照组：地图原生城邦 ############")
info(6, "原生城邦")

P("")
P("############ 验证 1+2：带【文明等级字符串】动态创建 ############")
local tIDs = try(function() return PlayerManager.GetAliveMinorIDs() end) or {}
local iOrigMinor = (type(tIDs)=="table" and #tIDs>0) and tIDs[1] or 6

-- 选一个池里但本局未出现的城邦：ARMAGH
local sCiv = "CIVILIZATION_ARMAGH"
local sLeader = try(function() return GameInfo.CivilizationLeaders[sCiv].LeaderType end)
P("  目标城邦 = "..sCiv.."   领袖查表 = "..tostring(sLeader))
P("  （验证 4：GameInfo.CivilizationLeaders 运行时是否可查）")

local iNew = tonumber(try(function() return tostring(pm:AddPlayer(true)) end))
P("  AddPlayer(true) -> "..tostring(iNew))

if iNew ~= nil then
  info(iNew, "STEP1")

  P("")
  P("  ⭐ SetPlayerLeader("..iNew..", "..tostring(sLeader)..", "..sCiv..", 'CIVILIZATION_LEVEL_CITY_STATE')")
  P("     -> "..try(function()
    pm:SetPlayerLeader(iNew, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE");
    return "called"
  end))
  info(iNew, "STEP2")

  P("")
  P("  ############ 关键判定 ############")
  P("    GetCivilizationLevelTypeName = "..
    try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
  P("    CanReceiveInfluence          = "..
    try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
  P("    CanAnnexTilesWithReceivedInfluence = "..
    try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))

  P("")
  P("  ############ 建城 ############")
  local tCities = {}
  for x = 0, 80 do
    for y = 0, 60 do
      local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
      if ok and c ~= nil then tCities[#tCities+1] = {x, y} end
    end
  end
  local spot = nil
  for x = 0, 80 do
    for y = 0, 60 do
      local p = Map.GetPlot(x, y)
      if p ~= nil then
        local w = try(function() return p:IsWater() end)
        local o = try(function() return p:GetOwner() end)
        if w == "false" and o == "-1" then
          local ok2 = true
          for _, cp in ipairs(tCities) do
            local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
            if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then ok2 = false; break end
          end
          if ok2 then spot = {x, y}; break end
        end
      end
    end
    if spot ~= nil then break end
  end
  if spot ~= nil then
    P(string.format("    建在 (%d,%d)", spot[1], spot[2]))
    try(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
    info(iNew, "STEP3")
    P("    城市名 = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("    类别   = "..try(function()
      local lt = PlayerConfigurations[iNew]:GetLeaderTypeName()
      return GameInfo.Leaders[lt].InheritFrom
    end))
    P("    建城后 CanReceiveInfluence = "..
      try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
  else
    P("    找不到空地")
  end
end

P("")
P("############ 验证 5（T-79）：先改槽状态、再设文明，能否激活预分配槽 ############")
-- 找一个状态=5 的预分配槽
local iPre = nil
for i = 0, 63 do
  if tonumber(try(function() return pm:GetSlotStatus(i) end)) == 5 then iPre = i; break end
end
if iPre == nil then
  P("  找不到状态=5 的槽")
else
  P("  取样预分配槽 = "..iPre.."  ("..
    try(function() return tostring(PlayerConfigurations[iPre]:GetCivilizationTypeName()) end)..")")
  info(iPre, "BEFORE")

  P("")
  P("  ① SetPlayerSlotStatus("..iPre..", SS_COMPUTER=1) -> "..try(function()
    return "returned "..tostring(pm:SetPlayerSlotStatus(iPre, SlotStatus.SS_COMPUTER))
  end))
  info(iPre, "AFTER-STATUS")

  P("")
  local sCiv2 = try(function() return tostring(PlayerConfigurations[iPre]:GetCivilizationTypeName()) end)
  local sLdr2 = try(function() return tostring(GameInfo.CivilizationLeaders[sCiv2].LeaderType) end)
  P("  ② SetPlayerLeader("..iPre..", "..tostring(sLdr2)..", "..tostring(sCiv2)..", 'CIVILIZATION_LEVEL_CITY_STATE')")
  P("     -> "..try(function()
    pm:SetPlayerLeader(iPre, sLdr2, sCiv2, "CIVILIZATION_LEVEL_CITY_STATE");
    return "called"
  end))
  info(iPre, "AFTER-LEADER")

  P("")
  P("  ③ 再试 InitializePlayer -> "..try(function()
    return "returned "..tostring(pm:InitializePlayer(iPre))
  end))
  info(iPre, "AFTER-INIT")
end

P("")
P("############ 汇总 ############")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  GetMaxPlayers = "..try(function() return pm:GetMaxPlayers() end))
P("  Turn = "..try(function() return Game.GetCurrentGameTurn() end))
"""
    + EPILOGUE
)


# ---- 40. 读档（专用探针，避免 --eval 被 PowerShell 按空格拆参数）----------
PROBES["loadsave"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local sName = "CSTEST_01";

P("== 读档 ==")
P("  存档名 = "..sName)

local tSaves = try(function() return Network.GetSaveGameList and "has_api" or "no_api" end)
P("  Network 表类型 = "..try(function() return type(Network) end))
P("  可用方法（采样）:")
for _, fn in ipairs({"LoadGame","SaveGame","GetGameConfigurationSaveType","GetSaveGameList"}) do
  P("    Network."..fn.." = "..try(function() return type(Network[fn]) end))
end
P("  SaveLocations.LOCAL_STORAGE = "..try(function() return tostring(SaveLocations.LOCAL_STORAGE) end))
P("  SaveTypes.SINGLE_PLAYER      = "..try(function() return tostring(SaveTypes.SINGLE_PLAYER) end))
P("  SaveDirectories.DEFAULT      = "..try(function() return tostring(SaveDirectories.DEFAULT) end))

local lg = {};
lg.Location  = SaveLocations.LOCAL_STORAGE;
lg.Type      = SaveTypes.SINGLE_PLAYER;
lg.IsAutosave  = false;
lg.IsQuicksave = false;
lg.Directory = SaveDirectories.DEFAULT;
lg.Name      = sName;

P("")
P("  调用 Network.LoadGame(...) -> "..try(function()
  local ok, res = pcall(function()
    return Network.LoadGame(lg, ServerType.SERVER_TYPE_NONE);
  end);
  return "ok="..tostring(ok).." res="..tostring(res);
end))
"""
    + EPILOGUE
)


# ---- 41. ⭐⭐⭐ 最小安全验证：只验「文明等级字符串」是否修好 CanReceiveInfluence ----
#   ⚠️ 刻意【不做】任何针对预分配槽（状态5）的操作——上一条探针 verify_cs 因动它们
#      导致 Unhandled Exception: EXCEPTION_ACCESS_VIOLATION（Error reading address 0x970）。
PROBES["verify_safe"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,55)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

local function info(i, tag)
  P(string.format("  [%-8s] 槽 %2d alive=%-5s init=%-5s lvl=%-30s canInf=%-5s cities=%s",
    tag, i,
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return tostring(PlayerConfigurations[i]:GetCivilizationLevelTypeName()) end),
    try(function() return tostring(Players[i]:GetInfluence():CanReceiveInfluence()) end),
    try(function() return tostring(Players[i]:GetCities():GetCount()) end)))
end

P("== 步骤 0：对照组（地图原生城邦）==")
-- ⚠️ 注意：try() 返回的是【字符串】，取表必须用 pcall 拿原值
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for i = 1, math.min(3, #tIDs) do info(tIDs[i], "原生") end

P("")
P("== 步骤 1：查领袖（验证运行时是否可查 GameInfo.CivilizationLeaders）==")
-- ⚠️ 用槽位转储里【亲眼见过】的城邦（ARMAGH），且必须验证领袖非 nil ——
--    给 SetPlayerLeader 传 nil 领袖会导致 C++ 空指针崩溃（EXCEPTION_ACCESS_VIOLATION 0x970）。
local sCiv = "CIVILIZATION_ARMAGH"
local kRow = nil
pcall(function() kRow = GameInfo.CivilizationLeaders[sCiv] end)
P("  GameInfo.CivilizationLeaders['"..sCiv.."'] = "..tostring(kRow ~= nil))
local sLeader = nil
if kRow ~= nil then
  pcall(function() sLeader = kRow.LeaderType end)
end
P("  领袖 = "..tostring(sLeader))

if sLeader == nil or sLeader == "" then
  P("")
  P("  ########## 【安全中止】##########")
  P("  领袖查不到（nil）——继续调用 SetPlayerLeader 会让引擎崩溃。")
  P("  请改用别的城邦，或先修好 CivilizationLeaders 的查法。")
else
P("")
P("== 步骤 2：AddPlayer ==")
local iNew = tonumber(try(function() return tostring(pm:AddPlayer(true)) end))
P("  -> "..tostring(iNew))
if iNew == nil then P("  【中止】AddPlayer 失败；游戏可能在主菜单状态") else
  info(iNew, "STEP2")

  P("")
  P("== 步骤 3：SetPlayerLeader ==")
  P("  先只用【已知安全】的写法（数字参数），把等级留给下一轮单独验")
  P("  SetPlayerLeader("..iNew..", '"..sLeader.."', '"..sCiv.."', 1)")
  P("  -> "..try(function()
    pm:SetPlayerLeader(iNew, sLeader, sCiv, 1);
    return "called"
  end))
  info(iNew, "STEP3")

  P("")
  P("  ########## 关键读取：等级到底是什么 ##########")
  P("    GetCivilizationLevelTypeName = "..
    try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
  P("    （把这个值与下面原生城邦的对比，就知道行序假设对不对）")
  P("    CanReceiveInfluence          = "..
    try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
  P("    GetTeam                      = "..
    try(function() return tostring(Players[iNew]:GetTeam()) end))
  P("    GetTreasury                  = "..
    try(function() return tostring(Players[iNew]:GetTreasury():GetGoldBalance()) end))

  P("")
  P("== 步骤 4：找空地建城 ==")
  local tCities = {}
  for x = 0, 80 do
    for y = 0, 60 do
      local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
      if ok and c ~= nil then tCities[#tCities+1] = {x, y} end
    end
  end
  local spot = nil
  for x = 0, 80 do
    for y = 0, 60 do
      local p = Map.GetPlot(x, y)
      if p ~= nil then
        local w = try(function() return p:IsWater() end)
        local o = try(function() return p:GetOwner() end)
        if w == "false" and o == "-1" then
          local ok2 = true
          for _, cp in ipairs(tCities) do
            local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
            if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then ok2 = false; break end
          end
          if ok2 then spot = {x, y}; break end
        end
      end
    end
    if spot ~= nil then break end
  end
  if spot == nil then P("  找不到空地") else
    P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
    try(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
    info(iNew, "STEP4")
    P("    城市名 = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("    建城后 CanReceiveInfluence = "..
      try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
  end
end

P("")
P("== 汇总 ==")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  Turn = "..try(function() return Game.GetCurrentGameTurn() end))
"""
    + EPILOGUE
)


# ---- 42. ⭐ 纯只读：文明等级与城邦对照（零风险，不动任何数据）-------------
PROBES["lvlread"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 各玩家类型的文明等级（只读）==")
P("  类型 | 槽 | 文明 | 等级 | CanReceiveInfluence")
local tMinor = {}
pcall(function() tMinor = PlayerManager.GetAliveMinorIDs() end)
local tMajor = {}
pcall(function() tMajor = PlayerManager.GetAliveMajorIDs() end)

for i = 1, math.min(3, #tMajor) do
  local id = tMajor[i]
  P(string.format("  主文明 | %2d | %-30s | %-30s | %s",
    id,
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end),
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationLevelTypeName()) end),
    try(function() return tostring(Players[id]:GetInfluence():CanReceiveInfluence()) end)))
end
for i = 1, math.min(4, #tMinor) do
  local id = tMinor[i]
  P(string.format("  城邦   | %2d | %-30s | %-30s | %s",
    id,
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end),
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationLevelTypeName()) end),
    try(function() return tostring(Players[id]:GetInfluence():CanReceiveInfluence()) end)))
end

P("")
P("== 2. CivilizationLevels 表全表（含 CanReceiveInfluence 字段）==")
local tLv = nil
pcall(function()
  tLv = DB.ConfigurationQuery(
    "SELECT CivilizationLevelType, CanReceiveInfluence, CanGiveInfluence, " ..
    "CanAnnexTilesWithReceivedInfluence, CanFoundCities, StartingTilesForCity " ..
    "FROM CivilizationLevels")
end)
if type(tLv) == "table" then
  for _, r in ipairs(tLv) do
    P(string.format("  %-32s canRecv=%-5s canGive=%-5s annexRecv=%-5s foundCities=%-5s tiles=%s",
      tostring(r.CivilizationLevelType), tostring(r.CanReceiveInfluence),
      tostring(r.CanGiveInfluence), tostring(r.CanAnnexTilesWithReceivedInfluence),
      tostring(r.CanFoundCities), tostring(r.StartingTilesForCity)))
  end
  P("  行序（= 可能的数字参数值）:")
  for i, r in ipairs(tLv) do
    P(string.format("    [%d] %s", i - 1, tostring(r.CivilizationLevelType)))
  end
else
  P("  查询失败")
end

P("")
P("== 3. 城邦文明的 StartingCivilizationLevelType（抽样）==")
local tCS = nil
pcall(function()
  tCS = DB.ConfigurationQuery(
    "SELECT CivilizationType, StartingCivilizationLevelType FROM Civilizations " ..
    "WHERE StartingCivilizationLevelType = 'CIVILIZATION_LEVEL_CITY_STATE' LIMIT 5")
end)
if type(tCS) == "table" then
  for _, r in ipairs(tCS) do
    P("  "..tostring(r.CivilizationType).." -> "..tostring(r.StartingCivilizationLevelType))
  end
  P("  （共 "..#tCS.." 条抽样）")
end

P("")
P("== 4. 文明→领袖映射能否运行时查询 ==")
local tCL = nil
pcall(function()
  tCL = DB.ConfigurationQuery(
    "SELECT CivilizationType, LeaderType FROM CivilizationLeaders " ..
    "WHERE CivilizationType IN ('CIVILIZATION_ARMAGH','CIVILIZATION_GENEVA','CIVILIZATION_KANDY')")
end)
if type(tCL) == "table" then
  for _, r in ipairs(tCL) do
    P("  "..tostring(r.CivilizationType).." -> "..tostring(r.LeaderType))
  end
else
  P("  查询失败")
end
local kTest = nil
pcall(function() kTest = GameInfo.CivilizationLeaders["CIVILIZATION_ARMAGH"] end)
P("  GameInfo.CivilizationLeaders['CIVILIZATION_ARMAGH'] 存在 = "..tostring(kTest ~= nil))
if kTest ~= nil then
  P("    其 LeaderType = "..try(function() return tostring(kTest.LeaderType) end))
end
"""
    + EPILOGUE
)


# ---- 43. 最小分离实验：只做 AddPlayer（不调 SetPlayerLeader，不建城）--------
#   目的：区分「是 AddPlayer 崩 还是 SetPlayerLeader 崩」
#   风险：低（AddPlayer 此前成功过 3 次）
PROBES["addonly"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,55)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = WorldBuilder.PlayerManager();

P("== 只读：动手前 ==")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  空槽（SS_CLOSED=2）清单:")
for i = 0, 63 do
  if tonumber(try(function() return pm:GetSlotStatus(i) end)) == 2 then
    P("    槽 "..i)
  end
end

P("")
P("== 唯一的写操作：AddPlayer(true) ==")
local iNew = nil
local sRet = try(function()
  iNew = pm:AddPlayer(true)
  return tostring(iNew)
end)
P("  返回 = "..sRet)

P("")
P("== 读回结果（不做任何后续写操作）==")
if iNew ~= nil and tonumber(sRet) ~= nil then
  local i = tonumber(sRet)
  P(string.format("  槽 %d: status=%s init=%s alive=%s major=%s civ=%s lvl=%s",
    i,
    try(function() return tostring(pm:GetSlotStatus(i)) end),
    try(function() return tostring(pm:IsPlayerInitialized(i)) end),
    try(function() return tostring(Players[i]:IsAlive()) end),
    try(function() return tostring(Players[i]:IsMajor()) end),
    try(function() return tostring(PlayerConfigurations[i]:GetCivilizationTypeName()) end),
    try(function() return tostring(PlayerConfigurations[i]:GetCivilizationLevelTypeName()) end)))
  P("  ⭐ 这一个槽的等级值就是【AddPlayer 默认给什么等级】的直接证据")
end

P("")
P("== 收尾只读 ==")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
"""
    + EPILOGUE
)


# ---- 44. 只读：前端扫视（用户停在哪个界面 / 地图列表是否为空）------------
PROBES["frontend"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 关键前端全局是否存在 ==")
-- ⚠️ 不能写 _G[n]：GameCore 沙箱里 _G 不存在（会报 attempt to index a nil value）。
--    必须直接按名字引用，用 pcall 包住。
P("  MapSelect       = "..try(function() return type(MapSelect) end))
P("  MainMenu        = "..try(function() return type(MainMenu) end))
P("  FrontEnd        = "..try(function() return type(FrontEnd) end))
P("  LoadGameMenu    = "..try(function() return type(LoadGameMenu) end))
P("  HostGame        = "..try(function() return type(HostGame) end))
P("  StagingRoom     = "..try(function() return type(StagingRoom) end))
P("  CityStatePicker = "..try(function() return type(CityStatePicker) end))
P("  LeaderPicker    = "..try(function() return type(LeaderPicker) end))

P("")
P("== 2. GameCore 全局（进对局后才有）==")
P("  Players       = "..try(function() return type(Players) end))
P("  PlayerManager = "..try(function() return type(PlayerManager) end))
P("  GameInfo      = "..try(function() return type(GameInfo) end))
P("  UnitManager   = "..try(function() return type(UnitManager) end))
P("  CityManager   = "..try(function() return type(CityManager) end))
P("  Game          = "..try(function() return type(Game) end))
P("  WorldBuilder  = "..try(function() return type(WorldBuilder) end))

P("")
P("== 3. 地图列表（若用户停在 MapSelect，这里能看出列表是否为空）==")
local tMaps = nil
pcall(function()
  tMaps = DB.ConfigurationQuery(
    "SELECT Map, Domain, Name, MapSizeType FROM Maps LIMIT 40")
end)
if type(tMaps) == "table" then
  P("  Maps 表条数（前 40）= "..#tMaps)
  for i = 1, math.min(10, #tMaps) do
    P("    "..tostring(tMaps[i].Map))
  end
else
  P("  查询失败（可能不在可查 DB 的上下文）")
end

P("")
P("== 4. 若在 MapSelect 上下文，读它的地图条目 ==")
local ok, ms = pcall(function() return MapSelect end)
P("  MapSelect 可取 = "..tostring(ok and ms ~= nil))
if ok and ms ~= nil then
  local n = 0
  for k, v in pairs(ms) do n = n + 1 end
  P("  其成员数 = "..n)
  for _, fn in ipairs({"GetMaps","m_Maps","m_MapEntries","m_MapList"}) do
    P(string.format("    %-16s = %s", fn, try(function() return type(ms[fn]) end)))
  end
end
"""
    + EPILOGUE
)


# ---- 45. ⭐⭐ 核心实验：AddPlayer 造的玩家是什么文明等级？能否修正？--------
#   这是"能否生成可正常外交交互的城邦"的决定性实验。
#   安全设计：**先读**（零风险）→ 只有确认等级不对才尝试修正 → 每步都读回。
PROBES["lvlfix"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then
  P("【中止】WorldBuilder.PlayerManager() 不可用（说明不在对局中）")
  P("  请确认 Lua 状态里有 GameCore_Tuner")
else

P("############ 阶段 1：只读——原生城邦的等级长什么样 ############")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  原生城邦数 = "..#tIDs)
for i = 1, math.min(4, #tIDs) do
  local id = tIDs[i]
  P(string.format("    槽 %2d  civ=%-28s  等级=%-32s  canInf=%s",
    id,
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end),
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationLevelTypeName()) end),
    try(function() return tostring(Players[id]:GetInfluence():CanReceiveInfluence()) end)))
end
P("")
P("  参考：主文明的等级")
local tMaj = {}
pcall(function() tMaj = PlayerManager.GetAliveMajorIDs() end)
if #tMaj > 0 then
  local id = tMaj[1]
  P(string.format("    槽 %2d  civ=%-28s  等级=%-32s  canInf=%s",
    id,
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end),
    try(function() return tostring(PlayerConfigurations[id]:GetCivilizationLevelTypeName()) end),
    try(function() return tostring(Players[id]:GetInfluence():CanReceiveInfluence()) end)))
end

P("")
P("  CivilizationLevels 表（含行序 = 可能的数字参数）:")
local tLv = nil
pcall(function()
  tLv = DB.ConfigurationQuery(
    "SELECT CivilizationLevelType, CanReceiveInfluence, StartingTilesForCity FROM CivilizationLevels")
end)
if type(tLv) == "table" then
  for i, r in ipairs(tLv) do
    P(string.format("    [%d] %-32s canRecv=%-5s tiles=%s",
      i - 1, tostring(r.CivilizationLevelType),
      tostring(r.CanReceiveInfluence), tostring(r.StartingTilesForCity)))
  end
end

P("")
P("  ⭐ 领袖查表测试（上两次崩溃的可疑点）:")
local kRow = nil
pcall(function() kRow = GameInfo.CivilizationLeaders["CIVILIZATION_ARMAGH"] end)
P("    GameInfo.CivilizationLeaders['CIVILIZATION_ARMAGH'] 存在 = "..tostring(kRow ~= nil))
local sLeader = nil
if kRow ~= nil then pcall(function() sLeader = kRow.LeaderType end) end
P("    其 LeaderType = "..tostring(sLeader))

P("")
P("############ 阶段 2：AddPlayer（唯一的写操作）############")
local iNew = nil
pcall(function() iNew = pm:AddPlayer(true) end)
P("  AddPlayer(true) -> "..tostring(iNew))
if iNew == nil or iNew == -1 then
  P("  【中止】AddPlayer 失败（空槽可能已用尽）")
else
  P(string.format("  ⭐ 新玩家【默认等级】= %s",
    try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end)))
  P(string.format("     此刻 civ=%s  alive=%s  canInf=%s",
    try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end),
    try(function() return tostring(Players[iNew]:IsAlive()) end),
    try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end)))

  P("")
  P("############ 阶段 3：SetPlayerLeader（第 4 参数传【数字】）############")
  P("  只在这一步之后读等级 —— 看数字参数是否影响等级")
  if sLeader == nil then
    P("  【跳过】领袖查不到，传 nil 会崩（T-84 教训）")
  else
    P("  SetPlayerLeader("..iNew..", '"..sLeader.."', 'CIVILIZATION_ARMAGH', 1)")
    local bOk = pcall(function()
      pm:SetPlayerLeader(iNew, sLeader, "CIVILIZATION_ARMAGH", 1)
    end)
    P("  -> "..tostring(bOk))
    P(string.format("     之后 civ=%-28s  等级=%-32s  canInf=%s",
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end),
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end),
      try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end)))
    P("")
    P("  ########## 结论判定 ##########")
    P("    若等级 = CIVILIZATION_LEVEL_CITY_STATE 且 canInf=true → 方案成立 ✅")
    P("    若等级 = FULL_CIV/TRIBE → 等级没被设对，需另寻他法")
  end
end

P("")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  Turn        = "..try(function() return Game.GetCurrentGameTurn() end))
end
"""
    + EPILOGUE
)


# ---- 46. ⭐ 代劳开局：调用引擎自带的快速开局入口 OnPlayCiv6() ----------------
#   依据：Base/Assets/UI/FrontEnd/MainMenu.lua:119-179
#     OnPlayCiv6() → LuaEvents.Raise_State_Transition("MainMenu")
#                   → BuildHeadlessGameSetup() → Network.HostGame(SERVER_TYPE_NONE)
#   用途：当用户停在前端不便操作时，用默认设置直接开一局，供对局内验证使用。
#   ⚠️ 副作用：会以【默认设置】覆盖当前的开局配置界面；仅供测试。
PROBES["startgame"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,70)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 快速开局入口是否存在 ==")
P("  OnPlayCiv6        = "..try(function() return type(OnPlayCiv6) end))
P("  BuildHeadlessGameSetup = "..try(function() return type(BuildHeadlessGameSetup) end))
P("  Network.HostGame  = "..try(function() return type(Network.HostGame) end))
P("  ServerType.SERVER_TYPE_NONE = "..try(function() return tostring(ServerType.SERVER_TYPE_NONE) end))

P("")
P("== 2. 调用 OnPlayCiv6() ==")
P("  -> "..try(function()
  local r = OnPlayCiv6()
  return "returned "..tostring(r)
end))

P("")
P("== 3. 立刻回读（开局是异步的，这里只看是否已发起）==")
P("  LuaEvents / 状态转换已触发则说明成功")
"""
    + EPILOGUE
)


# ---- 47. ⭐⭐⭐ 决定性验证 2：正确查领袖 + 传等级字符串 --------------------
#   基于 lvlfix 的结论：
#     · 原生城邦等级 = CIVILIZATION_LEVEL_CITY_STATE，canInf=true
#     · AddPlayer 造出的玩家【等级 = nil】→ 这就是 canInf=false 的原因
#     · GameInfo.CivilizationLeaders[civ] **查不到**（返回 nil）→ 这才是两次崩溃的真凶
#   本探针：改用 **SQL 查领袖**，然后传等级字符串，看能否一次修好。
PROBES["lvlfix2"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then
  P("【中止】WorldBuilder.PlayerManager() 不可用")
else

local sCiv = "CIVILIZATION_ARMAGH"

P("############ 1. 用 SQL 查领袖（GameInfo 查不到，改用 DB 查询）############")
P("  GameInfo.CivilizationLeaders 方式 = "..
  try(function() return tostring(GameInfo.CivilizationLeaders[sCiv] ~= nil) end))

local sLeader = nil
local tRows = nil
pcall(function()
  tRows = DB.ConfigurationQuery(
    "SELECT LeaderType FROM CivilizationLeaders WHERE CivilizationType = ?", sCiv)
end)
if type(tRows) == "table" and #tRows > 0 then
  pcall(function() sLeader = tRows[1].LeaderType end)
  P("  ⭐ SQL 查到的领袖 = "..tostring(sLeader))
else
  P("  SQL 也没查到（行数 = "..try(function() return tostring(type(tRows) == "table" and #tRows or "nil") end).."）")
  -- 退一步：从原生城邦玩家反推领袖（它们已经有正确领袖）
  local tIDs = {}
  pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
  for _, id in ipairs(tIDs) do
    local c = nil
    pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
    if c == sCiv then
      pcall(function() sLeader = PlayerConfigurations[id]:GetLeaderTypeName() end)
      P("  ⭐ 从原生城邦槽 "..id.." 反推到领袖 = "..tostring(sLeader))
      break
    end
  end
end

if sLeader == nil then
  P("")
  P("  【安全中止】领袖仍为 nil —— 传 nil 会崩（已确认真凶），不做后续写操作。")
else
  P("")
  P("############ 2. AddPlayer + SetPlayerLeader（领袖有效 + 等级字符串）############")
  local iNew = nil
  pcall(function() iNew = pm:AddPlayer(true) end)
  P("  AddPlayer -> "..tostring(iNew))
  if iNew ~= nil and iNew ~= -1 then
    P("    默认等级 = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))

    P("")
    P("  ① 先只设文明/领袖（不传等级），看等级是否自动变对")
    local b1 = pcall(function()
      pm:SetPlayerLeader(iNew, sLeader, sCiv, 1)
    end)
    P("     SetPlayerLeader(...,1) ok="..tostring(b1))
    P("     civ=%-28s 等级=%s" )
    P("     civ   = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
    P("     等级  = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
    P("     canInf= "..
      try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))

    P("")
    P("  ② 再传【等级字符串】")
    local b2 = pcall(function()
      pm:SetPlayerLeader(iNew, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE")
    end)
    P("     SetPlayerLeader(...,'CIVILIZATION_LEVEL_CITY_STATE') ok="..tostring(b2))
    P("     civ   = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
    P("     ⭐ 等级  = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
    P("     ⭐ canInf= "..
      try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))

    P("")
    P("     （若 b2 之后程序还活着且 canInf=true → 目标达成！）")
  end
end

P("")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
end
"""
    + EPILOGUE
)


# ---- 48. ⭐⭐⭐ 最小安全版：只用【已验证安全】的调用 -------------------------
#   教训（三次崩溃）：
#     · `GameInfo.CivilizationLeaders[civ]` → 查不到；**不要拿它做索引运算**
#     · **参数化 DB 查询（`?, x`）疑似崩溃源** —— 本探针一律不用
#     · 传 nil 领袖必崩
#   只用 lvlfix 里已经跑通过的安全调用：
#     PlayerConfigurations[id]:GetLeaderTypeName()   （从原生城邦反推领袖）
#     WorldBuilder.PlayerManager():AddPlayer(true)
#     WorldBuilder.PlayerManager():SetPlayerLeader(...)
PROBES["lvlmin"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

P("############ 1. 从已有城邦玩家反推领袖（已验证安全）############")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  存活城邦 = "..#tIDs)

local sCiv, sLeader = nil, nil
-- 优先挑 ARMAGH；没有就取第一个
for _, id in ipairs(tIDs) do
  local c, l = nil, nil
  pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
  pcall(function() l = PlayerConfigurations[id]:GetLeaderTypeName() end)
  if c == "CIVILIZATION_ARMAGH" then sCiv, sLeader = c, l; break end
  if sCiv == nil then sCiv, sLeader = c, l end
end
P("  选中 civ    = "..tostring(sCiv))
P("  对应领袖     = "..tostring(sLeader))
P("  （这个领袖是从真实城邦玩家读出来的，必然有效）")

if sLeader == nil or sCiv == nil then
  P("")
  P("  【安全中止】读不到有效领袖")
else
  P("")
  P("############ 2. AddPlayer ############")
  local iNew = nil
  pcall(function() iNew = pm:AddPlayer(true) end)
  P("  -> "..tostring(iNew))
  if iNew == nil or iNew == -1 then
    P("  【中止】AddPlayer 失败")
  else
    P("    默认等级 = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))

    P("")
    P("############ 3. SetPlayerLeader（领袖有效 + 等级字符串）############")
    P("  这一步是本次实验的核心：等级能不能被设成 CITY_STATE")
    local b = pcall(function()
      pm:SetPlayerLeader(iNew, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE")
    end)
    P("  调用成功 = "..tostring(b))
    P("")
    P("  ⭐ civ    = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
    P("  ⭐ 等级   = "..
      try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
    P("  ⭐ canInf = "..
      try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
    P("")
    P("  ########## 判定 ##########")
    P("    等级=CIVILIZATION_LEVEL_CITY_STATE 且 canInf=true → 【目标达成】")
    P("    否则 → 等级参数无效，需另寻他法")
  end
end

P("")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
end
"""
    + EPILOGUE
)


# ---- 49. ⭐⭐⭐ 完整链路验证：任意城邦 + 完整外交机制 -----------------------
#   基于 lvlmin 的成功结论（领袖从已有城邦反推 + 等级传字符串 → canInf=true），
#   本探针跑完整链条并在每步复查。
PROBES["verify_full"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then
  P("【中止】WorldBuilder 不可用（不在对局中？）")
else

P("========== 1. 挑一个目标城邦（用已有城邦的领袖）==========")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local sCiv, sLeader = nil, nil
for _, id in ipairs(tIDs) do
  local c, l = nil, nil
  pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
  pcall(function() l = PlayerConfigurations[id]:GetLeaderTypeName() end)
  if c ~= nil and l ~= nil and sCiv == nil then sCiv, sLeader = c, l end
end
P("  目标 civ = "..tostring(sCiv).."   领袖 = "..tostring(sLeader))

P("")
P("========== 2. AddPlayer + SetPlayerLeader（等级字符串）==========")
local iNew = nil
pcall(function() iNew = pm:AddPlayer(true) end)
P("  AddPlayer -> "..tostring(iNew))
local bFull = false
if iNew ~= nil and iNew ~= -1 and sLeader ~= nil then
  local b = pcall(function()
    pm:SetPlayerLeader(iNew, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE")
  end)
  P("  SetPlayerLeader ok="..tostring(b))
  P("    civ    = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
  P("    等级   = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
  local sInf = try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end)
  P("    canInf = "..sInf)
  bFull = (sInf == "true")

  P("")
  P("========== 3. 找空地建城 ==========")
  local tCities = {}
  for x = 0, 80 do
    for y = 0, 60 do
      local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
      if ok and c ~= nil then tCities[#tCities+1] = {x, y} end
    end
  end
  P("  场上已有城市 = "..#tCities.." 座")
  local spot = nil
  for x = 0, 80 do
    for y = 0, 60 do
      local p = Map.GetPlot(x, y)
      if p ~= nil then
        local w = try(function() return p:IsWater() end)
        local o = try(function() return p:GetOwner() end)
        if w == "false" and o == "-1" then
          local ok2 = true
          for _, cp in ipairs(tCities) do
            local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
            if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then ok2 = false; break end
          end
          if ok2 then spot = {x, y}; break end
        end
      end
    end
    if spot ~= nil then break end
  end

  if spot == nil then
    P("  【跳过】找不到合法空地")
  else
    P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
    local iBefore = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
    pcall(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
    local iAfter = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
    P(string.format("  cities %d -> %d", iBefore, iAfter))

    P("")
    P("========== 4. 完整机制复查 ==========")
    P("    格主     = "..try(function() return tostring(Map.GetPlot(spot[1], spot[2]):GetOwner()) end))
    P("    城市名   = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("    人口     = "..try(function() return tostring(CityManager.GetCityAt(spot[1], spot[2]):GetPopulation()) end))
    P("    Owner    = "..try(function() return tostring(CityManager.GetCityAt(spot[1], spot[2]):GetOwner()) end))
    P("    等级     = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
    P("    ⭐ canInf= "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
    P("    类别     = "..try(function()
      local lt = PlayerConfigurations[iNew]:GetLeaderTypeName()
      return tostring(GameInfo.Leaders[lt].InheritFrom)
    end))
    P("    IsMajor  = "..try(function() return tostring(Players[iNew]:IsMajor()) end))
    P("    IsAlive  = "..try(function() return tostring(Players[iNew]:IsAlive()) end))
    P("    本地玩家能否派使者 = "..try(function()
      return tostring(Players[Game.GetLocalPlayer()]:GetInfluence():CanGiveTokensToPlayer(iNew))
    end))
  end
end

P("")
P("========== 汇总 ==========")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  AliveMajors = "..try(function() return PlayerManager.GetAliveMajorsCount() end))
P("  Turn        = "..try(function() return Game.GetCurrentGameTurn() end))
end
"""
    + EPILOGUE
)


# ---- 50. ⭐⭐ 任意城邦的领袖查法（本局没有的城邦怎么拿领袖）----------------
#   背景：`GameInfo.CivilizationLeaders[civ]` 查不到；参数化 DB 查询疑似崩溃源。
#   本探针只测试【只读】的几种查法，不做任何写操作。
PROBES["leaderlookup"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local sCiv = "CIVILIZATION_KANDY"     -- 本局有没有都行，测的是查法本身

P("== 目标 civ = "..sCiv.." ==")

P("")
P("== 查法 A：GameInfo.CivilizationLeaders[civ] ==")
P("  type(GameInfo.CivilizationLeaders) = "..
  try(function() return type(GameInfo.CivilizationLeaders) end))
P("  [civ] 直接索引 = "..
  try(function() return tostring(GameInfo.CivilizationLeaders[sCiv]) end))

P("")
P("== 查法 B：遍历 GameInfo.CivilizationLeaders() 逐个比对 ==")
local sFound = nil
local n = 0
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    n = n + 1
    if row.CivilizationType == sCiv then
      sFound = row.LeaderType
    end
  end
end)
P("  迭代到 "..n.." 行")
P("  ⭐ 匹配到的领袖 = "..tostring(sFound))

P("")
P("== 查法 C：DB 查询（不带参数，用字符串拼接）==")
local t1 = nil
pcall(function()
  t1 = DB.ConfigurationQuery(
    "SELECT LeaderType FROM CivilizationLeaders WHERE CivilizationType = '" .. sCiv .. "'")
end)
if type(t1) == "table" and #t1 > 0 then
  P("  ⭐ 查到的领袖 = "..try(function() return tostring(t1[1].LeaderType) end))
else
  P("  失败或为空（type="..try(function() return tostring(type(t1)) end).."）")
end

P("")
P("== 查法 D：命名规律推导（CIVILIZATION_X -> LEADER_MINOR_CIV_X）==")
local sGuess = "LEADER_MINOR_CIV_" .. string.gsub(sCiv, "^CIVILIZATION_", "")
P("  推导 = "..sGuess)
local kL = nil
pcall(function() kL = GameInfo.Leaders[sGuess] end)
P("  GameInfo.Leaders[推导值] 存在 = "..tostring(kL ~= nil))

P("")
P("== 查法 E：从 Leaders 表按 InheritFrom 反查城邦领袖 ==")
local t2 = nil
pcall(function()
  t2 = DB.ConfigurationQuery(
    "SELECT LeaderType, InheritFrom FROM Leaders WHERE LeaderType LIKE 'LEADER_MINOR_CIV_%' LIMIT 5")
end)
if type(t2) == "table" then
  P("  城邦领袖示例（共查到 "..#t2.." 条）:")
  for _, r in ipairs(t2) do
    P("    "..tostring(r.LeaderType).."  InheritFrom="..tostring(r.InheritFrom))
  end
end
"""
    + EPILOGUE
)


# ---- 51. ⭐⭐⭐ 终极验证：建一个【本局没有的】任意城邦 ---------------------
PROBES["verify_any"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then
  P("【中止】WorldBuilder 不可用")
else

P("========== 1. 本局已有的城邦 ==========")
local tHave = {}
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local c = nil
  pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
  if c ~= nil then tHave[c] = true; P("    "..c) end
end

P("")
P("========== 2. 从【全池】里挑一个本局没有的城邦 ==========")
local tPool = {}
pcall(function()
  tPool = DB.ConfigurationQuery(
    "SELECT CivilizationType, Name FROM CityStates WHERE Domain = 'Expansion2CityStates'")
end)
P("  池内条数 = "..tostring(type(tPool) == "table" and #tPool or "nil"))

local sTarget = nil
if type(tPool) == "table" then
  for _, r in ipairs(tPool) do
    if not tHave[r.CivilizationType] then sTarget = r.CivilizationType; break end
  end
end
P("  ⭐ 选中的【本局没有的】城邦 = "..tostring(sTarget))

if sTarget == nil then
  P("  【中止】挑不到目标")
else
  P("")
  P("========== 3. 查它的领袖（遍历 CivilizationLeaders）==========")
  local sLeader = nil
  local n = 0
  pcall(function()
    for row in GameInfo.CivilizationLeaders() do
      n = n + 1
      if row.CivilizationType == sTarget then sLeader = row.LeaderType end
    end
  end)
  P("  遍历 "..n.." 行 → 领袖 = "..tostring(sLeader))

  if sLeader == nil then
    -- 兜底：命名规律 + 存在性验证
    local g = "LEADER_MINOR_CIV_" .. string.gsub(sTarget, "^CIVILIZATION_", "")
    local kL = nil
    pcall(function() kL = GameInfo.Leaders[g] end)
    if kL ~= nil then sLeader = g end
    P("  兜底推导 = "..g.."  存在="..tostring(kL ~= nil).."  → 采用 "..tostring(sLeader))
  end

  if sLeader == nil then
    P("  【安全中止】领袖查不到")
  else
    P("")
    P("========== 4. 建玩家 + 设文明/领袖/等级 ==========")
    local iNew = nil
    pcall(function() iNew = pm:AddPlayer(true) end)
    P("  AddPlayer -> "..tostring(iNew))
    if iNew ~= nil and iNew ~= -1 then
      local b = pcall(function()
        pm:SetPlayerLeader(iNew, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE")
      end)
      P("  SetPlayerLeader ok="..tostring(b))
      P("    civ    = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
      P("    等级   = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
      P("    ⭐ canInf = "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))

      P("")
      P("========== 5. 建城 ==========")
      local tCities = {}
      for x = 0, 80 do
        for y = 0, 60 do
          local ok, c = pcall(function() return CityManager.GetCityAt(x, y) end)
          if ok and c ~= nil then tCities[#tCities+1] = {x, y} end
        end
      end
      local spot = nil
      for x = 0, 80 do
        for y = 0, 60 do
          local p = Map.GetPlot(x, y)
          if p ~= nil then
            local w = try(function() return p:IsWater() end)
            local o = try(function() return p:GetOwner() end)
            if w == "false" and o == "-1" then
              local ok2 = true
              for _, cp in ipairs(tCities) do
                local dx, dy = math.abs(x - cp[1]), math.abs(y - cp[2])
                if math.max(dx, dy) + math.min(dx, dy) * 0.5 < 4 then ok2 = false; break end
              end
              if ok2 then spot = {x, y}; break end
            end
          end
        end
        if spot ~= nil then break end
      end
      if spot == nil then
        P("  【跳过】找不到空地")
      else
        P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
        local iB = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
        pcall(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
        local iA = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
        P(string.format("  cities %d -> %d", iB, iA))
        P("    城市名   = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
        P("    类别     = "..try(function()
          local lt = PlayerConfigurations[iNew]:GetLeaderTypeName()
          return tostring(GameInfo.Leaders[lt].InheritFrom)
        end))
        P("    ⭐ canInf= "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
      end
    end
  end
end

P("")
P("========== 汇总 ==========")
P("  AliveMinors = "..try(function() return PlayerManager.GetAliveMinorsCount() end))
P("  Turn        = "..try(function() return Game.GetCurrentGameTurn() end))
end
"""
    + EPILOGUE
)


# ---- 52. ⭐⭐⭐ 修复后回归测试：走【面板用的那个入口】建邦 -------------------
#   面板点击时调用的是 ExposedMembers.CSF.FoundCityStateByCiv(civ, x, y, unitID, ownerID)。
#   本探针直接调它，等于复现真实路径（含修复后的"先验证、后创建"顺序）。
PROBES["regress"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 面板入口是否已暴露 ==")
local fFound = nil
pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
P("  FoundCityStateByCiv    = "..try(function() return type(fFound) end))
local fGet = nil
pcall(function() fGet = ExposedMembers.CSF.GetFoundableCityStates end)
P("  GetFoundableCityStates = "..try(function() return type(fGet) end))
local fValid = nil
pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
P("  IsValidLocation        = "..try(function() return type(fValid) end))

P("")
P("== 2. 可建立城邦总数 ==")
local tList = nil
pcall(function() tList = fGet() end)
local sTarget = nil
if type(tList) == "table" then
  local nReuse = 0
  for _, e in ipairs(tList) do
    if e.CanReceiveInfluence then nReuse = nReuse + 1 end
  end
  P("  共 "..#tList.." 个（本局可复用 "..nReuse.." 个）")
  for _, e in ipairs(tList) do
    if not e.CanReceiveInfluence then sTarget = e.Civ; break end
  end
end
P("  挑中【需动态创建】的 = "..tostring(sTarget))

local iOwner = Game.GetLocalPlayer()

P("")
P("== 3. 用模组相同的校验函数找合法地点 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iOwner)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end

if spot == nil or sTarget == nil then
  P("  【中止】找不到合法地点或目标")
else
  P(string.format("  ✅ (%d,%d)", spot[1], spot[2]))

  P("")
  P("== 4. 走面板入口建邦 ==")
  local iB = 0
  pcall(function() iB = PlayerManager.GetAliveMinorsCount() end)
  P("  建邦前 AliveMinors = "..tostring(iB))

  local ok, bOk, sReason, iCs, bFull = pcall(fFound, sTarget, spot[1], spot[2], nil, iOwner)
  P("  pcall ok="..tostring(ok).."  bOk="..tostring(bOk)..
    "  reason="..tostring(sReason).."  player="..tostring(iCs)..
    "  bFull="..tostring(bFull))

  local iA = 0
  pcall(function() iA = PlayerManager.GetAliveMinorsCount() end)
  P("  AliveMinors "..tostring(iB).." -> "..tostring(iA))
  if iCs ~= nil then
    P("    文明     = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationTypeName()) end))
    P("    等级     = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationLevelTypeName()) end))
    P("    ⭐ canInf = "..try(function() return tostring(Players[iCs]:GetInfluence():CanReceiveInfluence()) end))
    P("    cities   = "..try(function() return tostring(Players[iCs]:GetCities():GetCount()) end))
    P("    城市名   = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("    格主     = "..try(function() return tostring(Map.GetPlot(spot[1], spot[2]):GetOwner()) end))
  end
end

P("")
P("========== 5. 非法地点回归（关键：不能再造出孤儿玩家）==========")
local iB2 = 0
pcall(function() iB2 = PlayerManager.GetAliveMinorsCount() end)
local badSpot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local p = Map.GetPlot(x, y)
    if p ~= nil and try(function() return p:IsWater() end) == "true" then
      badSpot = {x, y}; break
    end
  end
  if badSpot ~= nil then break end
end
if badSpot == nil or sTarget == nil then
  P("  （跳过）")
else
  local ok2, bOk2, sReason2 = pcall(fFound, sTarget, badSpot[1], badSpot[2], nil, iOwner)
  P(string.format("  水域 (%d,%d) 试建 -> ok=%s bOk=%s reason=%s",
    badSpot[1], badSpot[2], tostring(ok2), tostring(bOk2), tostring(sReason2)))
  local iA2 = 0
  pcall(function() iA2 = PlayerManager.GetAliveMinorsCount() end)
  P("  ⭐ AliveMinors "..tostring(iB2).." -> "..tostring(iA2))
  P("     【没变 = 修复生效：失败时不再创建孤儿玩家】")
end
"""
    + EPILOGUE
)


# ---- 53. ⭐⭐⭐ 隔离实验 A：在【UI 上下文】里调用（复现真实跨 VM 路径）------
#   真实使用时是 CSF_Panel（UI VM）调用 ExposedMembers.CSF.FoundCityStateByCiv（GameCore VM）。
#   我之前所有测试都在 GameCore_Tuner 里跑，**从未覆盖跨 VM 这条路径**。
#   本探针必须用 --state InGame（或 ActionPanel 等 UI 状态）运行。
PROBES["uicall"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 0. 确认当前跑在 UI 上下文（跨 VM 路径）==")
P("  ExposedMembers        = "..try(function() return type(ExposedMembers) end))
P("  ExposedMembers.CSF    = "..try(function() return type(ExposedMembers.CSF) end))
P("  Game.GetLocalPlayer   = "..try(function() return tostring(Game.GetLocalPlayer()) end))
P("  （若上面 CSF 为 nil，说明这个上下文拿不到 GameCore 的桥）")

local fFound, fGet, fValid = nil, nil, nil
pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
P("  FoundCityStateByCiv   = "..try(function() return type(fFound) end))
P("  GetFoundableCityStates= "..try(function() return type(fGet) end))
P("  IsValidLocation       = "..try(function() return type(fValid) end))

if fFound == nil or fGet == nil then
  P("")
  P("  【中止】这个上下文没有 CSF 桥（可能不在对局 UI 里）")
else

P("")
P("== 1. 取可建立城邦列表（跨 VM 调用 1）==")
local tList = nil
local okL, aL, bL = pcall(fGet)
P("  pcall ok="..tostring(okL))
if okL then tList = aL end
local sTarget = nil
if type(tList) == "table" then
  local nR = 0
  for _, e in ipairs(tList) do
    if e.CanReceiveInfluence then nR = nR + 1 end
  end
  P("  ✅ 收到 "..#tList.." 个（可复用 "..nR.." 个）")
  for _, e in ipairs(tList) do
    if not e.CanReceiveInfluence then sTarget = e.Civ; break end
  end
else
  P("  ❌ 返回类型 = "..try(function() return type(tList) end))
end
P("  目标 = "..tostring(sTarget))

P("")
P("== 2. 找一个【无主】的合法地点（与上次崩溃场景区分开）==")
local iOwner = Game.GetLocalPlayer()
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local p = Map.GetPlot(x, y)
    if p ~= nil then
      local w = try(function() return p:IsWater() end)
      local o = try(function() return tostring(p:GetOwner()) end)
      if w == "false" and o == "-1" then
        local ok, b = pcall(fValid, x, y, iOwner)
        if ok and b == true then spot = {x, y}; break end
      end
    end
  end
  if spot ~= nil then break end
end

if spot == nil or sTarget == nil then
  P("  【中止】条件不足")
else
  P(string.format("  ✅ (%d,%d)", spot[1], spot[2]))
  P("")
  P("== 3. 【跨 VM】调用建邦（不带单位 ID，先隔离出跨 VM 因素）==")
  local iB = 0; pcall(function() iB = PlayerManager.GetAliveMinorsCount() end)
  local okF, bOk, sReason, iCs, bFull = pcall(fFound, sTarget, spot[1], spot[2], nil, iOwner)
  P("  pcall ok="..tostring(okF).."  bOk="..tostring(bOk)..
    "  reason="..tostring(sReason).."  player="..tostring(iCs))
  local iA = 0; pcall(function() iA = PlayerManager.GetAliveMinorsCount() end)
  P("  AliveMinors "..tostring(iB).." -> "..tostring(iA))
  P("  【若这步崩了 → 跨 VM 调用本身不安全】")
  P("  【若这步成功 → 跨 VM 没问题，崩溃另有原因】")
end
end
"""
    + EPILOGUE
)


# ---- 54. ⭐⭐⭐ 隔离实验 B：在【有主地块】上建邦（tuner 上下文）-------------
#   新校验允许"自家领土"，于是 Create 会作用在【有主】地块上——这条路径从未测过。
PROBES["ownedplot"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fFound = nil
pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
local fGet = nil
pcall(function() fGet = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil
pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)

local iOwner = Game.GetLocalPlayer()
P("  本地玩家 = "..tostring(iOwner))

P("== 1. 找一个【本地玩家拥有】的合法地块 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local p = Map.GetPlot(x, y)
    if p ~= nil then
      local o = try(function() return tostring(p:GetOwner()) end)
      if o == tostring(iOwner) then
        local ok, b, why = pcall(fValid, x, y, iOwner)
        if ok and b == true then spot = {x, y}; break end
      end
    end
  end
  if spot ~= nil then break end
end

if spot == nil then
  P("  【跳过】本地玩家没有可用地块")
else
  P(string.format("  ✅ 有主地块 (%d,%d)  owner=%s", spot[1], spot[2], tostring(iOwner)))

  local sTarget = nil
  local tList = nil
  local okL, aL = pcall(fGet)
  if okL then tList = aL end
  if type(tList) == "table" then
    for _, e in ipairs(tList) do
      if not e.CanReceiveInfluence then sTarget = e.Civ; break end
    end
  end
  P("  目标城邦 = "..tostring(sTarget))

  if sTarget ~= nil then
    P("")
    P("== 2. 在【有主地块】上建邦 ==")
    P("  （新校验允许自家领土，所以会走到 Create 作用于有主地块）")
    local iB = 0; pcall(function() iB = PlayerManager.GetAliveMinorsCount() end)
    local okF, bOk, sReason, iCs = pcall(fFound, sTarget, spot[1], spot[2], nil, iOwner)
    P("  pcall ok="..tostring(okF).."  bOk="..tostring(bOk).."  reason="..tostring(sReason))
    local iA = 0; pcall(function() iA = PlayerManager.GetAliveMinorsCount() end)
    P("  AliveMinors "..tostring(iB).." -> "..tostring(iA))
    P("  【若这步崩了 → Create 不能作用于有主地块】")
  end
end
"""
    + EPILOGUE
)


# ---- 55. ⭐⭐⭐ 隔离实验 C：带【真实单位 ID】建邦（补齐唯一漏测变量）--------
#   此前 regress / uicall 都传了 iUnitID = nil → 整段"消耗使者"代码从未执行。
#   本探针先造一个真实的 UNIT_CSF_ENVOY，再用它的 ID 走完整流程。
PROBES["withunit"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fFound = nil; pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)

local iMe = Game.GetLocalPlayer()
P("  本地玩家 = "..tostring(iMe))

P("")
P("== 1. 找一个合法空地 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iMe)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end

if spot == nil then
  P("  【中止】没有合法空地")
else
  P(string.format("  ✅ (%d,%d)", spot[1], spot[2]))

  P("")
  P("== 2. 在该地块造一个真实的 UNIT_CSF_ENVOY ==")
  local pMe = Players[iMe]
  local pPlot = Map.GetPlot(spot[1], spot[2])
  local iUnit = nil
  local okS = pcall(function()
    iUnit = pMe:GetUnits():Create(pPlot, GameInfo.Units["UNIT_CSF_ENVOY"].Index, nil)
  end)
  P("  Create 单位 ok="..tostring(okS).."  单位ID="..tostring(iUnit))
  if iUnit == nil then
    P("  【中止】造单位失败（也许该地块已有单位）")
  else
    P("    单位类型 = "..try(function() return tostring(iUnit:GetType()) end))
    P("    坐标     = "..try(function() return tostring(iUnit:GetX())..","..tostring(iUnit:GetY()) end))
    local iUnitID = try(function() return tostring(iUnit:GetID()) end)
    P("    单位 ID  = "..iUnitID)

    P("")
    P("== 3. 【带真实单位 ID】调用建邦 ==")
    P("  ⚠️ 这一步会真正执行'消耗使者'的代码（此前从未测过）")
    local sTarget = nil
    local tL = nil; local okL, aL = pcall(fGet); if okL then tL = aL end
    if type(tL) == "table" then
      for _, e in ipairs(tL) do
        if not e.CanReceiveInfluence then sTarget = e.Civ; break end
      end
    end
    P("  目标城邦 = "..tostring(sTarget))
    if sTarget ~= nil then
      local okF, bOk, sReason, iCs = pcall(fFound, sTarget, spot[1], spot[2],
                                           tonumber(iUnitID), iMe)
      P("  pcall ok="..tostring(okF).."  bOk="..tostring(bOk).."  reason="..tostring(sReason))
      P("  城邦 player="..tostring(iCs))
      P("")
      P("  【若这步崩了 → '消耗使者'代码是崩溃点】")
      P("  【若这步成功 → 崩溃另有原因】")
    end
  end
end
"""
    + EPILOGUE
)


# ---- 56. ⭐⭐⭐ 验证【延迟执行】链路（RequestFound → 游戏事件处理）----------
PROBES["defertest"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fReq   = nil; pcall(function() fReq   = ExposedMembers.CSF.RequestFound end)
local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
P("  RequestFound          = "..try(function() return type(fReq) end))
P("  GetFoundableCityStates= "..try(function() return type(fGet) end))

local iMe = Game.GetLocalPlayer()

P("")
P("== 1. 找合法空地 + 目标城邦 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iMe)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end
local sTarget = nil
local tL = nil; local okL, aL = pcall(fGet); if okL then tL = aL end
if type(tL) == "table" then
  for _, e in ipairs(tL) do
    if not e.CanReceiveInfluence then sTarget = e.Civ; break end
  end
end
P("  地点 = "..try(function() return tostring(spot and spot[1])..","..tostring(spot and spot[2]) end))
P("  目标 = "..tostring(sTarget))

if spot ~= nil and sTarget ~= nil and fReq ~= nil then
  P("")
  P("== 2. 下单（只入队，不执行）==")
  local iB = 0; pcall(function() iB = PlayerManager.GetAliveMinorsCount() end)
  P("  下单前 AliveMinors = "..tostring(iB))
  local bQ = fReq(sTarget, spot[1], spot[2], nil, iMe)
  P("  入队 = "..tostring(bQ))
  local iA = 0; pcall(function() iA = PlayerManager.GetAliveMinorsCount() end)
  P("  下单后立即 AliveMinors = "..tostring(iA).."（应与下单前相同 = 确实没执行）")
  P("")
  P("  ⭐ 队列由 Events.GameCoreEventPublishComplete 消费。")
  P("     请【等待几秒后】查 Lua.log 里的 'processing queued request' / 'queued request result'。")
end
"""
    + EPILOGUE
)


# ---- 57. ⭐⭐⭐ UI 侧下单 + 结果回传闭环（必须用 --state InGame 跑）---------
#   复现真实使用：UI 上下文下单 → GameCore 事件执行 → GameEvents 广播回 UI。
PROBES["uidefer"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 0. UI 上下文确认 ==")
P("  ExposedMembers.CSF = "..try(function() return type(ExposedMembers.CSF) end))
P("  GameEvents         = "..try(function() return type(GameEvents) end))
P("  GameEvents.CSF_FoundResult = "..
  try(function() return type(GameEvents.CSF_FoundResult) end))

-- UI 侧注册监听（模拟 CSF_Panel 的做法），确认能收到回传
local bGot = false
pcall(function()
  GameEvents.CSF_FoundResult.Add(function(bOk, sReason, iCs, x, y)
    bGot = true
    print("[uidefer] ⭐ UI 收到结果: ok="..tostring(bOk)..
          " reason="..tostring(sReason).." player="..tostring(iCs))
  end)
end)
P("  已注册 GameEvents.CSF_FoundResult 监听")

local fReq   = nil; pcall(function() fReq   = ExposedMembers.CSF.RequestFound end)
local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
P("  RequestFound = "..try(function() return type(fReq) end))

local iMe = Game.GetLocalPlayer()

P("")
P("== 1. 找合法空地 + 目标城邦 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iMe)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end
local sTarget = nil
local tL = nil; local okL, aL = pcall(fGet); if okL then tL = aL end
if type(tL) == "table" then
  for _, e in ipairs(tL) do
    if not e.CanReceiveInfluence then sTarget = e.Civ; break end
  end
end
P("  地点 = "..try(function() return tostring(spot and spot[1])..","..tostring(spot and spot[2]) end))
P("  目标 = "..tostring(sTarget))

if spot ~= nil and sTarget ~= nil and fReq ~= nil then
  P("")
  P("== 2. 【UI 侧】下单 ==")
  local bQ = fReq(sTarget, spot[1], spot[2], nil, iMe)
  P("  入队 = "..tostring(bQ))
  P("  ⭐ 等 GameCore 事件处理器执行，结果会广播回这里的监听")
end
"""
    + EPILOGUE
)


# ---- 58. ⭐⭐⭐ 测【重定向】路径：建一个本局没有的任意城邦 ------------------
PROBES["retarget"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fFound = nil; pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
local fReq   = nil; pcall(function() fReq   = ExposedMembers.CSF.RequestFound end)

local iMe = Game.GetLocalPlayer()
P("  本地玩家 = "..tostring(iMe))

P("")
P("== 1. 本局已有的城邦 ==")
local tHave = {}
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local c = nil
  pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
  local n = 0
  pcall(function() n = Players[id]:GetCities():GetCount() end)
  P(string.format("    槽 %2d  %-30s cities=%d", id, tostring(c), n))
  if c ~= nil then tHave[c] = true end
end

P("")
P("== 2. 从池里挑一个【本局没有的】城邦 ==")
local tPool = nil
pcall(function()
  tPool = DB.ConfigurationQuery(
    "SELECT CivilizationType FROM CityStates WHERE Domain = 'Expansion2CityStates'")
end)
local sTarget = nil
if type(tPool) == "table" then
  for _, r in ipairs(tPool) do
    if not tHave[r.CivilizationType] then sTarget = r.CivilizationType; break end
  end
end
P("  ⭐ 选中 = "..tostring(sTarget))

P("")
P("== 3. 找合法空地 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iMe)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end
P("  地点 = "..try(function() return tostring(spot and spot[1])..","..tostring(spot and spot[2]) end))

if spot ~= nil and sTarget ~= nil then
  P("")
  P("== 4. 走【重定向】路径建邦（直接调用，避开延迟队列）==")
  local iB = 0; pcall(function() iB = PlayerManager.GetAliveMinorsCount() end)
  P("  建邦前 AliveMinors = "..tostring(iB))

  local ok, bOk, sReason, iCs, bFull = pcall(fFound, sTarget, spot[1], spot[2], nil, iMe)
  P("  pcall ok="..tostring(ok).."  bOk="..tostring(bOk)..
    "  reason="..tostring(sReason).."  player="..tostring(iCs)..
    "  bFull="..tostring(bFull))

  local iA = 0; pcall(function() iA = PlayerManager.GetAliveMinorsCount() end)
  P("  AliveMinors "..tostring(iB).." -> "..tostring(iA))
  if iCs ~= nil and iCs >= 0 then
    P("    ⭐ 文明   = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationTypeName()) end))
    P("    ⭐ 领袖   = "..try(function() return tostring(PlayerConfigurations[iCs]:GetLeaderTypeName()) end))
    P("    ⭐ 等级   = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationLevelTypeName()) end))
    P("    ⭐ canInf = "..try(function() return tostring(Players[iCs]:GetInfluence():CanReceiveInfluence()) end))
    P("    cities   = "..try(function() return tostring(Players[iCs]:GetCities():GetCount()) end))
    P("    城市名   = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("    格主     = "..try(function() return tostring(Map.GetPlot(spot[1], spot[2]):GetOwner()) end))
  end
end
"""
    + EPILOGUE
)


# ---- 59. ⭐⭐⭐ 端到端：UI 上下文下单 + 轮询取结果（完全模拟真实点击）-------
PROBES["e2e"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,60)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 0. 上下文 ==")
P("  ExposedMembers.CSF = "..try(function() return type(ExposedMembers.CSF) end))
P("  GameEvents         = "..try(function() return type(GameEvents) end).."（nil = 走轮询兜底）")

local fReq = nil; pcall(function() fReq = ExposedMembers.CSF.RequestFound end)
local fGet = nil; pcall(function() fGet = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
local fLast = nil; pcall(function() fLast = ExposedMembers.CSF.GetLastResult end)
P("  RequestFound   = "..try(function() return type(fReq) end))
P("  GetLastResult  = "..try(function() return type(fLast) end))

local iMe = Game.GetLocalPlayer()

P("")
P("== 1. 找一个【本局没有的】城邦 ==")
local tHave = {}
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local c = nil; pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
  if c ~= nil then tHave[c] = true end
end
local tPool = nil
pcall(function()
  tPool = DB.ConfigurationQuery(
    "SELECT CivilizationType FROM CityStates WHERE Domain = 'Expansion2CityStates'")
end)
local sTarget = nil
if type(tPool) == "table" then
  for _, r in ipairs(tPool) do
    if not tHave[r.CivilizationType] then sTarget = r.CivilizationType; break end
  end
end
P("  ⭐ 目标 = "..tostring(sTarget))

P("")
P("== 2. 找合法空地 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iMe)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end
P("  地点 = "..try(function() return tostring(spot and spot[1])..","..tostring(spot and spot[2]) end))

if sTarget ~= nil and spot ~= nil then
  P("")
  P("== 3. 【UI 侧下单】==")
  local iSeqBefore = 0
  if fLast ~= nil then
    local okS, s0 = pcall(fLast)
    if okS then iSeqBefore = tonumber(s0) or 0 end
  end
  P("  下单前结果序号 = "..tostring(iSeqBefore))
  local bQ = fReq(sTarget, spot[1], spot[2], nil, iMe)
  P("  入队 = "..tostring(bQ))
  P("  ⭐ 等 GameCore 事件处理器执行（约 1~2 秒），然后轮询结果")
end
"""
    + EPILOGUE
)


# ---- 60. ⭐⭐⭐ 诊断：重定向后的玩家与原生城邦差在哪（traits/颜色/加成）------
PROBES["retargetdiag"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,55)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 全部城邦玩家的 traits / 颜色 对比 ==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local p = Players[id]
  if p ~= nil then
    local sCiv = try(function() return tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end)
    local sLdr = try(function() return tostring(PlayerConfigurations[id]:GetLeaderTypeName()) end)
    local n    = 0
    pcall(function() n = p:GetCities():GetCount() end)
    P(string.format("  槽 %2d cities=%d  civ=%-32s", id, n, sCiv))
    P(string.format("         leader=%s", sLdr))

    -- traits
    local pTraits = nil
    pcall(function() pTraits = p:GetTraits() end)
    if pTraits ~= nil then
      local tList = {}
      pcall(function()
        for row in pTraits:Members() do
          local s = nil
          pcall(function()
            s = GameInfo.Traits[row]:TraitType()
          end)
          tList[#tList+1] = tostring(s or row)
        end
      end)
      P("         traits("..#tList..") = "..table.concat(tList, ", "))
    else
      P("         traits = "..try(function() return type(pTraits) end))
    end

    -- 颜色
    local kColor = nil
    pcall(function() kColor = PlayerConfigurations[id]:GetColor() end)
    if kColor ~= nil then
      local s1 = try(function() return tostring(kColor.PrimaryColor) end)
      local s2 = try(function() return tostring(kColor.SecondaryColor) end)
      P("         color: primary="..s1.." secondary="..s2)
    end
  end
end

P("")
P("== 2. CityStates 表里的加成定义（看加成挂在哪个 Trait 上）==")
local tCS = nil
pcall(function()
  tCS = DB.ConfigurationQuery(
    "SELECT CivilizationType, Name, CityStateCategory, Bonus, Bonus_XP1, Bonus_XP2 " ..
    "FROM CityStates WHERE CivilizationType IN " ..
    "('CIVILIZATION_ANTANANARIVO','CIVILIZATION_BABYLON','CIVILIZATION_JERUSALEM')")
end)
if type(tCS) == "table" then
  for _, r in ipairs(tCS) do
    P("  "..tostring(r.CivilizationType).." cat="..tostring(r.CityStateCategory)..
      " Bonus="..tostring(r.Bonus).." XP2="..tostring(r.Bonus_XP2))
  end
end

P("")
P("== 3. 城邦加成的 Modifier 挂在哪个 Trait 上 ==")
local tTM = nil
pcall(function()
  tTM = DB.ConfigurationQuery(
    "SELECT TraitType, ModifierId FROM TraitModifiers " ..
    "WHERE TraitType LIKE '%ANTANANARIVO%' OR TraitType LIKE '%BABYLON%' LIMIT 10")
end)
if type(tTM) == "table" then
  for _, r in ipairs(tTM) do
    P("  "..tostring(r.TraitType).."  ->  "..tostring(r.ModifierId))
  end
  P("  （共 "..#tTM.." 条）")
else
  P("  查询失败或为空")
end

P("")
P("== 4. 领袖的 Trait 定义 ==")
local tLT = nil
pcall(function()
  tLT = DB.ConfigurationQuery(
    "SELECT LeaderType, TraitType FROM LeaderTraits " ..
    "WHERE LeaderType IN ('LEADER_MINOR_CIV_ANTANANARIVO','LEADER_MINOR_CIV_JERUSALEM','LEADER_MINOR_CIV_BABYLON')")
end)
if type(tLT) == "table" then
  for _, r in ipairs(tLT) do
    P("  "..tostring(r.LeaderType).."  ->  "..tostring(r.TraitType))
  end
end
"""
    + EPILOGUE
)


# ---- 61. ⭐⭐⭐ 诊断2：重定向后 PlayerConfigurations 各项是否一致 -------------
PROBES["pcdiag"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  槽 | CivType | Leader | ShortDesc | Desc | Color | Name")
for _, id in ipairs(tIDs) do
  local pc = PlayerConfigurations[id]
  if pc ~= nil then
    local n = 0; pcall(function() n = Players[id]:GetCities():GetCount() end)
    P(string.format("--- 槽 %d (cities=%d) ---", id, n))
    P("   CivType    = "..try(function() return tostring(pc:GetCivilizationTypeName()) end))
    P("   Leader     = "..try(function() return tostring(pc:GetLeaderTypeName()) end))
    P("   ⭐ ShortDesc = "..try(function() return tostring(pc:GetCivilizationShortDescription()) end))
    P("   ⭐ Desc      = "..try(function() return tostring(pc:GetCivilizationDescription()) end))
    P("   CivName(键) = "..try(function() return tostring(pc:GetCivilizationName()) end))
    P("   PlayerName  = "..try(function() return tostring(pc:GetPlayerName()) end))
    P("   Color       = "..try(function() return tostring(pc:GetColor()) end))
    P("   Level       = "..try(function() return tostring(pc:GetCivilizationLevelTypeName()) end))
  end
end

P("")
P("== 对照：DB 里 ANTANANARIVO 该显示什么 ==")
local tCS = nil
pcall(function()
  tCS = DB.ConfigurationQuery(
    "SELECT CivilizationType, Name, CityStateCategory FROM CityStates " ..
    "WHERE CivilizationType='CIVILIZATION_ANTANANARIVO'")
end)
if type(tCS) == "table" then
  for _, r in ipairs(tCS) do
    P("  Name="..tostring(r.Name).."  cat="..tostring(r.CityStateCategory))
  end
end
"""
    + EPILOGUE
)


# ---- 62. ⭐⭐⭐⭐ 实验：用 UninitializePlayer + InitializePlayer 重建玩家 -----
#   目标：让玩家以【目标城邦】的身份被重新初始化 → 颜色与特性都正确。
#   安全设计：每步都读回状态；一旦异常就停。
PROBES["rebuild"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then
  P("【中止】WorldBuilder 不可用")
else

P("== 0. PlayerManager 是否有这两个方法 ==")
P("  UninitializePlayer = "..try(function() return type(pm.UninitializePlayer) end))
P("  InitializePlayer   = "..try(function() return type(pm.InitializePlayer) end))

-- 快照函数：读一个城邦玩家的完整状态
local function snap(id, tag)
  local pc = PlayerConfigurations[id]
  P(string.format("  [%s] 槽%d civ=%s", tag, id,
    try(function() return tostring(pc:GetCivilizationTypeName()) end)))
  P(string.format("        leader=%s  color=%s",
    try(function() return tostring(pc:GetLeaderTypeName()) end),
    try(function() return tostring(pc:GetColor()) end)))
  P(string.format("        shortDesc=%s",
    try(function() return tostring(pc:GetCivilizationShortDescription()) end)))
  P(string.format("        inited=%s  cities=%s",
    try(function() return tostring(pm:IsPlayerInitialized(id)) end),
    try(function() return tostring(Players[id]:GetCities():GetCount()) end)))
end

P("")
P("== 1. 选一个休眠城邦玩家 ==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iVictim = nil
for _, id in ipairs(tIDs) do
  local n = 0
  pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iVictim == nil then iVictim = id end
end
P("  选中 = "..tostring(iVictim))
if iVictim == nil then
  P("  【中止】没有休眠城邦")
else
  snap(iVictim, "改之前")

  -- 目标文明
  local sTarget = "CIVILIZATION_ANTANANARIVO"
  local sLeader = nil
  pcall(function()
    for row in GameInfo.CivilizationLeaders() do
      if row.CivilizationType == sTarget then sLeader = row.LeaderType end
    end
  end)
  P("")
  P("  目标 = "..sTarget.."  领袖 = "..tostring(sLeader))

  if sLeader == nil then
    P("  【中止】查不到领袖")
  else
    P("")
    P("== 2. 【A】先单独试 UninitializePlayer ==")
    local b1 = pcall(function() pm:UninitializePlayer(iVictim) end)
    P("  UninitializePlayer ok="..tostring(b1))
    snap(iVictim, "uninit后")

    P("")
    P("== 3. 【B】设新文明 ==")
    local b2 = pcall(function()
      pm:SetPlayerLeader(iVictim, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE")
    end)
    P("  SetPlayerLeader ok="..tostring(b2))
    snap(iVictim, "setLeader后")

    P("")
    P("== 4. 【C】再 InitializePlayer（关键：看颜色/名字会不会刷新）==")
    local b3 = pcall(function() pm:InitializePlayer(iVictim) end)
    P("  InitializePlayer ok="..tostring(b3))
    snap(iVictim, "init后")

    P("")
    P("  ########## 判定 ##########")
    P("  对比 shortDesc / color 是否随文明变化：")
    P("   · 若变了 → 重建方案可行 ✅")
    P("   · 若没变 → 引擎确实不给运行时改")
  end
end
end
"""
    + EPILOGUE
)


# ---- 63. ⭐⭐⭐⭐⭐ 实验2：重建玩家 → 建城 → 完整验证 -----------------------
PROBES["rebuild2"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

-- 取一个休眠城邦
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iVictim = nil
for _, id in ipairs(tIDs) do
  local n = 0
  pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iVictim == nil then iVictim = id end
end
P("  休眠城邦 = "..tostring(iVictim))

local sTarget = "CIVILIZATION_ANTANANARIVO"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)

if iVictim == nil or sLeader == nil then
  P("  【中止】条件不足")
else
  P(string.format("  改造：槽%d  %s  →  %s", iVictim,
    try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationTypeName()) end),
    sTarget))

  P("")
  P("== 1. UninitializePlayer ==")
  P("  ok="..try(function() pm:UninitializePlayer(iVictim); return "true" end))

  P("")
  P("== 2. SetPlayerLeader（带等级字符串）==")
  P("  ok="..try(function()
    pm:SetPlayerLeader(iVictim, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE");
    return "true"
  end))
  P("     civ       = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationTypeName()) end))
  P("     color     = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetColor()) end))
  P("     shortDesc = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationShortDescription()) end))
  P("     inited    = "..try(function() return tostring(pm:IsPlayerInitialized(iVictim)) end))

  P("")
  P("== 3. InitializePlayer ==")
  P("  ok="..try(function() pm:InitializePlayer(iVictim); return "true" end))
  P("     inited    = "..try(function() return tostring(pm:IsPlayerInitialized(iVictim)) end))
  P("     alive     = "..try(function() return tostring(Players[iVictim]:IsAlive()) end))
  P("     canInf    = "..try(function() return tostring(Players[iVictim]:GetInfluence():CanReceiveInfluence()) end))
  P("     units     = "..try(function()
    local n = 0
    for _ in Players[iVictim]:GetUnits():Members() do n = n + 1 end
    return n
  end))

  P("")
  P("== 4. 找一个合法空地并建城 ==")
  local spot = nil
  for x = 0, 80 do
    for y = 0, 60 do
      local p = Map.GetPlot(x, y)
      if p ~= nil then
        local w = try(function() return p:IsWater() end)
        local o = try(function() return tostring(p:GetOwner()) end)
        if w == "false" and o == "-1" then spot = {x, y}; break end
      end
    end
    if spot ~= nil then break end
  end
  if spot == nil then P("  【跳过】无空地") else
    P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
    local iB = tonumber(try(function() return tostring(Players[iVictim]:GetCities():GetCount()) end)) or 0
    pcall(function() Players[iVictim]:GetCities():Create(spot[1], spot[2]) end)
    local iA = tonumber(try(function() return tostring(Players[iVictim]:GetCities():GetCount()) end)) or 0
    P(string.format("  cities %d -> %d", iB, iA))

    P("")
    P("== 5. 完整验证 ==")
    P("     civ       = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationTypeName()) end))
    P("     leader    = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetLeaderTypeName()) end))
    P("     level     = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationLevelTypeName()) end))
    P("     ⭐ color     = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetColor()) end))
    P("     ⭐ shortDesc = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationShortDescription()) end))
    P("     ⭐ canInf    = "..try(function() return tostring(Players[iVictim]:GetInfluence():CanReceiveInfluence()) end))
    P("     cities    = "..try(function() return tostring(Players[iVictim]:GetCities():GetCount()) end))
    P("     城市名    = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
    P("     格主      = "..try(function() return tostring(Map.GetPlot(spot[1], spot[2]):GetOwner()) end))
  end
end
end
"""
    + EPILOGUE
)


# ---- 64. ⭐⭐⭐⭐⭐ 实验3：拆开 → 改名 → 补起始位置 → 重建 -------------------
PROBES["rebuild3"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iVictim = nil
for _, id in ipairs(tIDs) do
  local n = 0
  pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iVictim == nil then iVictim = id end
end
local sTarget = "CIVILIZATION_ANTANANARIVO"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)

P("  休眠城邦 = "..tostring(iVictim).."   目标 = "..sTarget)

if iVictim == nil or sLeader == nil then
  P("  【中止】条件不足")
else
  P("")
  P("== 步骤 1: UninitializePlayer ==")
  P("  ok="..try(function() pm:UninitializePlayer(iVictim); return "true" end))

  P("== 步骤 2: SetPlayerLeader（新文明 + 等级）==")
  P("  ok="..try(function()
    pm:SetPlayerLeader(iVictim, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE");
    return "true"
  end))
  P("     color="..try(function() return tostring(PlayerConfigurations[iVictim]:GetColor()) end))

  P("== 步骤 3: SetRandomMinorStartingPosition（补起始位置）==")
  P("  ok="..try(function() pm:SetRandomMinorStartingPosition(iVictim); return "true" end))

  P("== 步骤 4: InitializePlayer ==")
  P("  ok="..try(function() pm:InitializePlayer(iVictim); return "true" end))

  P("")
  P("== 复查 ==")
  P("     inited = "..try(function() return tostring(pm:IsPlayerInitialized(iVictim)) end))
  local p = Players[iVictim]
  P("     Players[id] = "..try(function() return type(p) end))
  if p ~= nil then
    P("     alive  = "..try(function() return tostring(p:IsAlive()) end))
    P("     canInf = "..try(function() return tostring(p:GetInfluence():CanReceiveInfluence()) end))
    P("     cities = "..try(function() return tostring(p:GetCities():GetCount()) end))
  end
end
end
"""
    + EPILOGUE
)


# ---- 65. ⭐⭐⭐⭐⭐ 实验4：先改名 → 再拆开重建（换顺序）----------------------
PROBES["rebuild4"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iVictim = nil
for _, id in ipairs(tIDs) do
  local n = 0
  pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iVictim == nil then iVictim = id end
end
local sTarget = "CIVILIZATION_ANTANANARIVO"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)
P("  休眠城邦 = "..tostring(iVictim).."   目标 = "..sTarget)

if iVictim == nil or sLeader == nil then
  P("  【中止】条件不足")
else
  P("")
  P("== 方案 B：先改名（保持活着）→ 再拆开重建 ==")
  P("  步骤 1: SetPlayerLeader（新文明，玩家仍初始化状态）")
  P("    ok="..try(function()
    pm:SetPlayerLeader(iVictim, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE");
    return "true"
  end))
  P("       color="..try(function() return tostring(PlayerConfigurations[iVictim]:GetColor()) end))
  P("       alive="..try(function() return tostring(Players[iVictim]:IsAlive()) end))

  P("  步骤 2: UninitializePlayer")
  P("    ok="..try(function() pm:UninitializePlayer(iVictim); return "true" end))

  P("  步骤 3: InitializePlayer")
  P("    ok="..try(function() pm:InitializePlayer(iVictim); return "true" end))

  P("")
  P("  复查：")
  P("     inited = "..try(function() return tostring(pm:IsPlayerInitialized(iVictim)) end))
  P("     color  = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetColor()) end))
  P("     shortD = "..try(function() return tostring(PlayerConfigurations[iVictim]:GetCivilizationShortDescription()) end))
  P("     alive  = "..try(function() return tostring(Players[iVictim]:IsAlive()) end))
  P("     canInf = "..try(function() return tostring(Players[iVictim]:GetInfluence():CanReceiveInfluence()) end))
end
end
"""
    + EPILOGUE
)


# ---- 66. ⭐⭐⭐⭐⭐ 实验5：AddPlayer 后立刻改名，再补位置 ----------------------
PROBES["addthenfix"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

local sTarget = "CIVILIZATION_ANTANANARIVO"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)
P("  目标 = "..sTarget.."  领袖 = "..tostring(sLeader))

if sLeader == nil then
  P("  【中止】查不到领袖")
else
  P("")
  P("== AddPlayer → SetPlayerLeader → SetRandomMinorStartingPosition ==")
  local iNew = nil
  pcall(function() iNew = pm:AddPlayer(true) end)
  P("  AddPlayer -> "..tostring(iNew))
  if iNew == nil or iNew == -1 then
    P("  【中止】AddPlayer 失败（空槽用尽）")
  else
    P("    默认 color = "..try(function() return tostring(PlayerConfigurations[iNew]:GetColor()) end))
    P("    默认 lvl   = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))

    P("  SetPlayerLeader -> "..try(function()
      pm:SetPlayerLeader(iNew, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE");
      return "ok"
    end))
    P("    ⭐ color     = "..try(function() return tostring(PlayerConfigurations[iNew]:GetColor()) end))
    P("    ⭐ shortDesc = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationShortDescription()) end))
    P("    ⭐ level     = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))

    P("  SetRandomMinorStartingPosition -> "..try(function()
      pm:SetRandomMinorStartingPosition(iNew); return "ok"
    end))

    P("")
    P("  复查：")
    P("     inited = "..try(function() return tostring(pm:IsPlayerInitialized(iNew)) end))
    P("     alive  = "..try(function() return tostring(Players[iNew]:IsAlive()) end))
    P("     canInf = "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
    P("     color  = "..try(function() return tostring(PlayerConfigurations[iNew]:GetColor()) end))
    P("     shortD = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationShortDescription()) end))
  end
end
end
"""
    + EPILOGUE
)


# ---- 67. ⭐⭐⭐⭐⭐ 终极验证：AddPlayer 路径建城 + 完整复查 -------------------
PROBES["final"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

local sTarget = "CIVILIZATION_BABYLON"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)
P("  目标 = "..sTarget.."  领袖 = "..tostring(sLeader))

if sLeader == nil then
  P("  【中止】查不到领袖")
else
  P("")
  P("== 1. AddPlayer ==")
  local iNew = nil
  pcall(function() iNew = pm:AddPlayer(true) end)
  P("  -> "..tostring(iNew))
  if iNew == nil or iNew == -1 then
    P("  【中止】空槽用尽")
  else
    P("== 2. SetPlayerLeader ==")
    local b = pcall(function()
      pm:SetPlayerLeader(iNew, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE")
    end)
    P("  ok="..tostring(b))
    P("== 3. SetRandomMinorStartingPosition ==")
    P("  ok="..try(function() pm:SetRandomMinorStartingPosition(iNew); return "true" end))

    P("")
    P("== 4. 找合法空地建城 ==")
    local spot = nil
    for x = 0, 80 do
      for y = 0, 60 do
        local p = Map.GetPlot(x, y)
        if p ~= nil then
          local w = try(function() return p:IsWater() end)
          local o = try(function() return tostring(p:GetOwner()) end)
          if w == "false" and o == "-1" then spot = {x, y}; break end
        end
      end
      if spot ~= nil then break end
    end
    if spot == nil then P("  【跳过】无空地") else
      P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
      local iB = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
      pcall(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
      local iA = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
      P(string.format("  cities %d -> %d", iB, iA))

      P("")
      P("========== 完整复查 ==========")
      P("     civ       = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
      P("     leader    = "..try(function() return tostring(PlayerConfigurations[iNew]:GetLeaderTypeName()) end))
      P("     level     = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationLevelTypeName()) end))
      P("     ⭐ color     = "..try(function() return tostring(PlayerConfigurations[iNew]:GetColor()) end))
      P("     ⭐ shortDesc = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationShortDescription()) end))
      P("     ⭐ canInf    = "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))
      P("     cities    = "..try(function() return tostring(Players[iNew]:GetCities():GetCount()) end))
      P("     城市名    = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
      P("     格主      = "..try(function() return tostring(Map.GetPlot(spot[1], spot[2]):GetOwner()) end))
      P("     IsMajor   = "..try(function() return tostring(Players[iNew]:IsMajor()) end))

      -- 对照：一个原生城邦的颜色，判断新玩家的颜色是否"像城邦色"
      local tIDs = {}
      pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
      P("")
      P("  对照（原生城邦的颜色）:")
      for i = 1, math.min(4, #tIDs) do
        local id = tIDs[i]
        if id ~= iNew then
          P(string.format("     槽%2d %s color=%s", id,
            try(function() return tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end),
            try(function() return tostring(PlayerConfigurations[id]:GetColor()) end)))
        end
      end
    end
  end
end
end
"""
    + EPILOGUE
)


# ---- 68. ⭐⭐⭐⭐⭐ 复现用户场景：使节【站在那一格上】再建邦 -----------------
PROBES["withunit2"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fFound = nil; pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)

local iMe = Game.GetLocalPlayer()
P("  本地玩家 = "..tostring(iMe))

P("")
P("== 1. 找一个合法空地 ==")
local spot = nil
for x = 0, 80 do
  for y = 0, 60 do
    local ok, b = pcall(fValid, x, y, iMe)
    if ok and b == true then spot = {x, y}; break end
  end
  if spot ~= nil then break end
end
P("  地点 = "..try(function() return tostring(spot and spot[1])..","..tostring(spot and spot[2]) end))

if spot == nil then
  P("  【中止】没有合法空地")
else
  P("")
  P("== 2. 在该格上生成一个真实的地图内使节 ==")
  local pMe = Players[iMe]
  local iUnit = nil
  -- 与预留路径同款 API：InitUnit(owner, type, x, y)
  local okI = pcall(function()
    iUnit = UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", spot[1], spot[2])
  end)
  P("  InitUnit ok="..tostring(okI).."  返回="..try(function() return type(iUnit) end))
  local iUnitID = nil
  if iUnit ~= nil then
    iUnitID = tonumber(try(function() return tostring(iUnit:GetID()) end))
    P("     单位ID = "..tostring(iUnitID))
    P("     坐标   = "..try(function() return tostring(iUnit:GetX())..","..tostring(iUnit:GetY()) end))
  end

  P("")
  P("== 3. 挑一个本局没有的城邦 ==")
  local tHave = {}
  local tIDs = {}
  pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
  for _, id in ipairs(tIDs) do
    local c = nil; pcall(function() c = PlayerConfigurations[id]:GetCivilizationTypeName() end)
    if c ~= nil then tHave[c] = true end
  end
  local tPool = nil
  pcall(function()
    tPool = DB.ConfigurationQuery(
      "SELECT CivilizationType FROM CityStates WHERE Domain = 'Expansion2CityStates'")
  end)
  local sTarget = nil
  if type(tPool) == "table" then
    for _, r in ipairs(tPool) do
      if not tHave[r.CivilizationType] then sTarget = r.CivilizationType; break end
    end
  end
  P("  目标 = "..tostring(sTarget))

  P("")
  P("== 4. ⭐ 带【真实单位 ID】建邦（单位就在那一格上）==")
  P("  这正是用户崩溃的场景")
  if sTarget ~= nil then
    local iB = 0; pcall(function() iB = PlayerManager.GetAliveMinorsCount() end)
    local ok, bOk, sReason, iCs = pcall(fFound, sTarget, spot[1], spot[2], iUnitID, iMe)
    P("  pcall ok="..tostring(ok).."  bOk="..tostring(bOk)..
      "  reason="..tostring(sReason).."  player="..tostring(iCs))
    local iA = 0; pcall(function() iA = PlayerManager.GetAliveMinorsCount() end)
    P("  AliveMinors "..tostring(iB).." -> "..tostring(iA))
    if iCs ~= nil and iCs >= 0 then
      P("     civ    = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationTypeName()) end))
      P("     color  = "..try(function() return tostring(PlayerConfigurations[iCs]:GetColor()) end))
      P("     shortD = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationShortDescription()) end))
      P("     canInf = "..try(function() return tostring(Players[iCs]:GetInfluence():CanReceiveInfluence()) end))
      P("     cities = "..try(function() return tostring(Players[iCs]:GetCities():GetCount()) end))
    end
    -- 使节应该已被消耗
    P("  使节是否还在 = "..try(function()
      return tostring(UnitManager.GetUnit(iMe, iUnitID) ~= nil)
    end))
  end
end
"""
    + EPILOGUE
)


# ---- 69. 诊断：UI.GetPlayerColors 对新玩家返回什么（必须用 --state InGame）----
PROBES["colors"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("  UI.GetPlayerColors = "..try(function() return type(UI.GetPlayerColors) end))

local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("")
P("  槽 | config color | UI.GetPlayerColors(back, front)")
for _, id in ipairs(tIDs) do
  local c = try(function() return tostring(PlayerConfigurations[id]:GetColor()) end)
  local ok, back, front = pcall(UI.GetPlayerColors, id)
  P(string.format("  %2d | %-12s | ok=%s back=%s front=%s",
    id, c, tostring(ok), tostring(back), tostring(front)))
end

P("")
P("  对照：本地玩家（0）")
local ok0, b0, f0 = pcall(UI.GetPlayerColors, 0)
P("     ok="..tostring(ok0).." back="..tostring(b0).." front="..tostring(f0))
"""
    + EPILOGUE
)


# ---- 70. ⭐⭐⭐⭐⭐ 方案：释放一个 UI 认识的槽 → AddPlayer 拿回 → 改名 --------
#   动机：`UI.GetPlayerColors(54)` = nil（C++ 内部颜色表只认识开局时的玩家）。
#   而 UninitializePlayer 释放的槽会被 AddPlayer 重新拿到，那些槽 UI 认识。
PROBES["slotreuse"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

-- 找一个休眠城邦（0 城）
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iVictim = nil
for _, id in ipairs(tIDs) do
  local n = 0
  pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iVictim == nil then iVictim = id end
end
P("  休眠城邦（准备释放）= "..tostring(iVictim))

local sTarget = "CIVILIZATION_ANTIOCH"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)

if iVictim == nil or sLeader == nil then
  P("  【中止】条件不足")
else
  P("")
  P("== 1. 释放槽 "..iVictim.."（UI 的颜色表认识它）==")
  P("  UninitializePlayer ok="..try(function() pm:UninitializePlayer(iVictim); return "true" end))

  P("== 2. AddPlayer（期望拿回同一个槽）==")
  local iNew = nil
  pcall(function() iNew = pm:AddPlayer(true) end)
  P("  AddPlayer -> "..tostring(iNew).."（期望 = "..tostring(iVictim).."）")
  P("  ⭐ 是否复用成功 = "..tostring(iNew == iVictim))

  if iNew == nil or iNew == -1 then
    P("  【中止】AddPlayer 失败")
  else
    P("== 3. SetPlayerLeader ==")
    P("  ok="..try(function()
      pm:SetPlayerLeader(iNew, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE");
      return "true"
    end))
    P("== 4. SetRandomMinorStartingPosition ==")
    P("  ok="..try(function() pm:SetRandomMinorStartingPosition(iNew); return "true" end))

    P("")
    P("  复查：")
    P("     civ    = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationTypeName()) end))
    P("     color  = "..try(function() return tostring(PlayerConfigurations[iNew]:GetColor()) end))
    P("     shortD = "..try(function() return tostring(PlayerConfigurations[iNew]:GetCivilizationShortDescription()) end))
    P("     inited = "..try(function() return tostring(pm:IsPlayerInitialized(iNew)) end))
    P("     alive  = "..try(function() return tostring(Players[iNew]:IsAlive()) end))
    P("     canInf = "..try(function() return tostring(Players[iNew]:GetInfluence():CanReceiveInfluence()) end))

    P("")
    P("  ⭐⭐ 颜色查询必须在 --state InGame 里做（GameCore 没有 UI 全局）。")
    P("      本探针跑完请另开一次： cs_probe.py --probe colors --state InGame")

    P("")
    P("== 5. 建城 ==")
    local spot = nil
    for x = 0, 80 do
      for y = 0, 60 do
        local p = Map.GetPlot(x, y)
        if p ~= nil then
          local w = try(function() return p:IsWater() end)
          local o = try(function() return tostring(p:GetOwner()) end)
          if w == "false" and o == "-1" then spot = {x, y}; break end
        end
      end
      if spot ~= nil then break end
    end
    if spot == nil then P("  【跳过】无空地") else
      P(string.format("  建在 (%d,%d)", spot[1], spot[2]))
      local iB = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
      pcall(function() Players[iNew]:GetCities():Create(spot[1], spot[2]) end)
      local iA = tonumber(try(function() return tostring(Players[iNew]:GetCities():GetCount()) end)) or 0
      P(string.format("  cities %d -> %d", iB, iA))
      P("     城市名 = "..try(function() return CityManager.GetCityAt(spot[1], spot[2]):GetName() end))
      P("     格主   = "..try(function() return tostring(Map.GetPlot(spot[1], spot[2]):GetOwner()) end))
    end
  end
end
end
"""
    + EPILOGUE
)


# ---- 71. ⭐⭐⭐⭐⭐ 自检：新建玩家 vs 原生城邦，逐个字段对比 -----------------
#   目的：找出新建玩家【缺什么】（外交状态 / 颜色 / …），而不是让你去发现。
PROBES["selftest"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

-- 收集一个城邦玩家的全部关键字段
local function dump(id, tag)
  local pc = PlayerConfigurations[id]
  local p  = Players[id]
  P("--- ["..tag.."] 槽 "..id.." ---")
  P("    civ        = "..try(function() return tostring(pc:GetCivilizationTypeName()) end))
  P("    leader     = "..try(function() return tostring(pc:GetLeaderTypeName()) end))
  P("    level      = "..try(function() return tostring(pc:GetCivilizationLevelTypeName()) end))
  P("    shortDesc  = "..try(function() return tostring(pc:GetCivilizationShortDescription()) end))
  P("    color      = "..try(function() return tostring(pc:GetColor()) end))
  P("    team       = "..try(function() return tostring(pc:GetTeam()) end))
  P("    isAlive    = "..try(function() return tostring(p:IsAlive()) end))
  P("    isMajor    = "..try(function() return tostring(p:IsMajor()) end))
  P("    cities     = "..try(function() return tostring(p:GetCities():GetCount()) end))
  P("    canInf     = "..try(function() return tostring(p:GetInfluence():CanReceiveInfluence()) end))

  -- ⭐ 外交：这是 BetterCityStates 崩在第 374 行的原因
  local iDiplo = nil
  local okD = pcall(function()
    -- 取它跟本地玩家的外交状态
    local iLocal = Game.GetLocalPlayer()
    iDiplo = p:GetDiplomaticAI():GetDiplomaticStateIndex(iLocal)
  end)
  P("    ⭐ diploIdx(vs 本地) = "..tostring(okD and iDiplo or ("ERR:"..tostring(iDiplo))))
  if okD and iDiplo ~= nil then
    local kDS = nil
    pcall(function() kDS = GameInfo.DiplomaticStates[iDiplo] end)
    P("    ⭐ DiplomaticStates[idx] = "..tostring(kDS ~= nil)..
      (kDS ~= nil and ("  StateType="..tostring(kDS.StateType)) or "   ← ⚠️ nil 会让 BetterCityStates 崩"))
  end
  -- 与其他玩家的外交
  local nBad = 0
  for _, other in ipairs(PlayerManager.GetAliveMajorIDs()) do
    local idx = nil
    pcall(function() idx = p:GetDiplomaticAI():GetDiplomaticStateIndex(other) end)
    local ok2 = false
    pcall(function() ok2 = GameInfo.DiplomaticStates[idx] ~= nil end)
    if not ok2 then nBad = nBad + 1 end
  end
  P("    ⭐ 对主文明的外交状态里【无效的条数】= "..nBad)

  -- traits（有没有别的读法）
  P("    GetTraitModifiers? = "..try(function() return type(p.GetTraitModifiers) end))
  P("    GetDiplomacy       = "..try(function() return type(p.GetDiplomacy) end))
  P("    GetDiplomaticAI    = "..try(function() return type(p.GetDiplomaticAI) end))
end

-- 先建一个新玩家（走与 MOD 相同的步骤）
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

P("========== A. 原生城邦（对照）==========")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
if #tIDs > 0 then dump(tIDs[1], "原生") end

P("")
P("========== B. 新建玩家（走 MOD 步骤）==========")
local sTarget = "CIVILIZATION_AKKAD"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)

local iNew = nil
pcall(function() iNew = pm:AddPlayer(true) end)
P("  AddPlayer -> "..tostring(iNew))
if iNew ~= nil and iNew ~= -1 then
  pcall(function() pm:SetPlayerLeader(iNew, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE") end)
  pcall(function() pm:SetRandomMinorStartingPosition(iNew) end)
  dump(iNew, "新建")

  P("")
  P("========== C. 尝试补齐外交状态 ==========")
  P("  可用的补齐手段探测：")
  local p = Players[iNew]
  local d = nil
  pcall(function() d = p:GetDiplomacy() end)
  if d ~= nil then
    for _, m in ipairs({"SetHasMet","SetVisibilityOn","DeclareWarOn","MakePeaceWith","SetHasAllied","SetHasDeclaredFriendship"}) do
      P("    Diplomacy."..m.." = "..try(function() return type(d[m]) end))
    end
  end
  local ai = nil
  pcall(function() ai = p:GetDiplomaticAI() end)
  if ai ~= nil then
    for _, m in ipairs({"SetDiplomaticState","GetDiplomaticStateIndex","SetDiplomaticStateIndex","Initialize"}) do
      P("    DiplomaticAI."..m.." = "..try(function() return type(ai[m]) end))
    end
  end
end
end
"""
    + EPILOGUE
)


# ---- 72. ⭐⭐⭐⭐⭐ 自检2：释放已有槽 → AddPlayer 拿回 → 改名 → 全面对比 ------
PROBES["selftest2"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function dump(id, tag)
  local pc = PlayerConfigurations[id]
  local p  = Players[id]
  P("--- ["..tag.."] 槽 "..id.." ---")
  P("    civ="..try(function() return tostring(pc:GetCivilizationTypeName()) end)..
    "  leader="..try(function() return tostring(pc:GetLeaderTypeName()) end))
  P("    shortDesc="..try(function() return tostring(pc:GetCivilizationShortDescription()) end))
  P("    color="..try(function() return tostring(pc:GetColor()) end))
  P("    isAlive="..try(function() return tostring(p:IsAlive()) end)..
    "  cities="..try(function() return tostring(p:GetCities():GetCount()) end)..
    "  canInf="..try(function() return tostring(p:GetInfluence():CanReceiveInfluence()) end))
  local ai = nil
  pcall(function() ai = p:GetDiplomaticAI() end)
  P("    GetDiplomaticAI() = "..try(function() return type(ai) end))
  if ai ~= nil then
    P("      SetDiplomaticState      = "..try(function() return type(ai.SetDiplomaticState) end))
    P("      SetDiplomaticStateIndex = "..try(function() return type(ai.SetDiplomaticStateIndex) end))
    P("      GetDiplomaticStateIndex = "..try(function() return type(ai.GetDiplomaticStateIndex) end))
  end
  local d = nil
  pcall(function() d = p:GetDiplomacy() end)
  if d ~= nil then
    P("    Diplomacy.SetHasMet = "..try(function() return type(d.SetHasMet) end))
  end
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  本局城邦 = "..(#tIDs).." 个")

P("")
P("========== A. 原生城邦（对照，含 GetDiplomaticAI 探测）==========")
if #tIDs > 0 then dump(tIDs[1], "原生") end

-- 找一个休眠城邦作为"牺牲品"
local iVictim = nil
for _, id in ipairs(tIDs) do
  local n = 0; pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iVictim == nil then iVictim = id end
end
P("")
P("  选中要释放的槽 = "..tostring(iVictim))

local sTarget = "CIVILIZATION_AKKAD"
local sLeader = nil
pcall(function()
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sTarget then sLeader = row.LeaderType end
  end
end)

if iVictim ~= nil and sLeader ~= nil then
  P("")
  P("========== B. 释放槽 "..iVictim.." ==========")
  P("  UninitializePlayer ok="..try(function() pm:UninitializePlayer(iVictim); return "true" end))

  P("========== C. AddPlayer（期望拿回同一个槽）==========")
  local iNew = nil
  pcall(function() iNew = pm:AddPlayer(true) end)
  P("  AddPlayer -> "..tostring(iNew).."   （原槽 = "..tostring(iVictim).."）")
  P("  ⭐ 复用成功 = "..tostring(iNew == iVictim))

  if iNew ~= nil and iNew ~= -1 then
    pcall(function() pm:SetPlayerLeader(iNew, sLeader, sTarget, "CIVILIZATION_LEVEL_CITY_STATE") end)
    pcall(function() pm:SetRandomMinorStartingPosition(iNew) end)
    P("")
    P("========== D. 结果对比 ==========")
    dump(iNew, "新建(复用槽)")
  end
end
end
"""
    + EPILOGUE
)


# ---- 73. ⭐⭐⭐⭐⭐ 安全路径自检：连续复建本局已有的城邦，逐步验证 ------------
PROBES["safetest"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fFound = nil; pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)
local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)

local iMe = Game.GetLocalPlayer()

P("== 1. 面板数据（应只列可用的那些）==")
local tList = nil
local okL, aL = pcall(fGet); if okL then tList = aL end
local tReuse = {}
if type(tList) == "table" then
  for _, e in ipairs(tList) do
    if e.Mode == "reuse" then tReuse[#tReuse+1] = e.Civ end
  end
  P("  共 "..#tList.." 个，其中 reuse（可用）="..#tReuse)
end

if #tReuse == 0 then
  P("  【中止】没有可复用的城邦")
else
  -- 挑最多 3 个做测试
  local nTest = math.min(3, #tReuse)
  for k = 1, nTest do
    local sCiv = tReuse[k]
    P("")
    P("========== 测试 "..k.."/"..nTest.."： "..sCiv.." ==========")

    -- 找合法空地
    local spot = nil
    for x = 0, 80 do
      for y = 0, 60 do
        local ok, b = pcall(fValid, x, y, iMe)
        if ok and b == true then spot = {x, y}; break end
      end
      if spot ~= nil then break end
    end
    if spot == nil then
      P("  【跳过】无合法空地")
    else
      -- 造一个真实的地图内使节
      local iUnit = nil
      pcall(function() iUnit = UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", spot[1], spot[2]) end)
      local iUnitID = nil
      if iUnit ~= nil then iUnitID = tonumber(try(function() return tostring(iUnit:GetID()) end)) end
      P(string.format("  使节 id=%s @(%d,%d)", tostring(iUnitID), spot[1], spot[2]))

      local ok, bOk, sReason, iCs = pcall(fFound, sCiv, spot[1], spot[2], iUnitID, iMe)
      P("  建邦 -> ok="..tostring(ok).." bOk="..tostring(bOk)..
        " reason="..tostring(sReason).." player="..tostring(iCs))
      if iCs ~= nil and iCs >= 0 then
        P("     civ    = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationTypeName()) end))
        P("     color  = "..try(function() return tostring(PlayerConfigurations[iCs]:GetColor()) end))
        P("     shortD = "..try(function() return tostring(PlayerConfigurations[iCs]:GetCivilizationShortDescription()) end))
        P("     canInf = "..try(function() return tostring(Players[iCs]:GetInfluence():CanReceiveInfluence()) end))
        P("     cities = "..try(function() return tostring(Players[iCs]:GetCities():GetCount()) end))
      end
      P("     使节是否还在 = "..try(function()
        return tostring(UnitManager.GetUnit(iMe, iUnitID) ~= nil)
      end))
    end
  end

  P("")
  P("========== 汇总 ==========")
  P("  AliveMinors = "..try(function() return tostring(PlayerManager.GetAliveMinorsCount()) end))
  P("  若上面 3 次都 bOk=true 且游戏未崩 → 安全路径可用 ✅")
end
"""
    + EPILOGUE
)


# ---- 74. ⭐⭐⭐⭐⭐ 关键实验：UI.RebuildColorDB() 能否让新玩家获得颜色 ---------
#   背景：EXE 绑定表里有 GetPlayerColors / RefreshColorSet / RebuildColorDB。
#   假设：颜色表是开局建立的，新玩家不在其中；重建后应该就能查到。
PROBES["colordb"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. UI 上的颜色相关接口是否存在 ==")
for _, n in ipairs({"GetPlayerColors","RebuildColorDB","RefreshColorSet","GetPlayerColorValues",
                    "ArePlayerColorsConflicting","GetColorValue","GetColors"}) do
  local f = nil
  pcall(function() f = UI[n] end)
  P(string.format("  UI.%-26s = %s", n, try(function() return type(f) end)))
end

P("")
P("== 2. 找一个【没有任何颜色】的玩家（新建的槽 54 若存在）==")
local iTarget = nil
for id = 54, 63 do
  local pc = PlayerConfigurations[id]
  if pc ~= nil then
    local ok, b, f = pcall(UI.GetPlayerColors, id)
    if ok and b == nil then iTarget = id; break end
  end
end
P("  找到无颜色的槽 = "..tostring(iTarget))

P("")
P("== 3. 调用 RebuildColorDB / RefreshColorSet ==")
P("  UI.RebuildColorDB()    -> "..try(function() UI.RebuildColorDB(); return "ok" end))
P("  UI.RefreshColorSet()   -> "..try(function() UI.RefreshColorSet(); return "ok" end))

P("")
P("== 4. 复查颜色 ==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local ok, b, f = pcall(UI.GetPlayerColors, id)
  P(string.format("    槽 %2d back=%s front=%s", id, tostring(b), tostring(f)))
end
if iTarget ~= nil then
  local ok, b, f = pcall(UI.GetPlayerColors, iTarget)
  P(string.format("    ⭐ 目标槽 %d back=%s front=%s  （若不再是 nil → 方案成立！）",
    iTarget, tostring(b), tostring(f)))
end
"""
    + EPILOGUE
)


# ---- 75. ⭐⭐⭐⭐⭐ 关键实验2：新建玩家 + 补齐颜色/外交 --------------------
#   A) UI 侧：UI.RebuildColorDB() / UI.RefreshColorSet() 能否让新玩家有颜色
#   B) GameCore 侧：MakePeaceWith / SetHasMet 能否建立外交状态
PROBES["fixall"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

-- ==== 阶段 1：UI 侧的颜色接口探测（只有 UI 上下文才有 UI 全局）====
local bHasUI = false
pcall(function() bHasUI = (type(UI) == "table") end)
P("  本上下文有 UI 全局 = "..tostring(bHasUI))

if bHasUI then
  P("")
  P("== A. 颜色接口 ==")
  for _, n in ipairs({"GetPlayerColors","RebuildColorDB","RefreshColorSet"}) do
    P(string.format("  UI.%-18s = %s", n, try(function() return type(UI[n]) end)))
  end
  -- 找一个没颜色的槽
  local iNoColor = nil
  for id = 54, 63 do
    local pc = PlayerConfigurations[id]
    if pc ~= nil then
      local ok, b = pcall(UI.GetPlayerColors, id)
      if ok and b == nil then iNoColor = id; break end
    end
  end
  P("  无颜色的槽 = "..tostring(iNoColor))
  P("  重建前 UI.GetPlayerColors(54) = "..
    try(function()
      local _, b, f = UI.GetPlayerColors(54)
      return tostring(b).."/"..tostring(f)
    end))
  P("  ⭐ UI.RebuildColorDB() -> "..try(function() UI.RebuildColorDB(); return "ok" end))
  P("  ⭐ UI.RefreshColorSet() -> "..try(function() UI.RefreshColorSet(); return "ok" end))
  P("  重建后 UI.GetPlayerColors(54) = "..
    try(function()
      local _, b, f = UI.GetPlayerColors(54)
      return tostring(b).."/"..tostring(f)
    end))
end

-- ==== 阶段 2：GameCore 侧的外交接口探测（WorldBuilder 只有 GameCore 有）====
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm ~= nil then
  P("")
  P("== B. 外交接口（GameCore 侧）==")
  local tIDs = {}
  pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
  local iProbe = tIDs[1]
  if iProbe ~= nil then
    local p = Players[iProbe]
    local d = nil
    pcall(function() d = p:GetDiplomacy() end)
    if d ~= nil then
      for _, n in ipairs({"SetHasMet","MakePeaceWith","DeclareWarOn","HasMet","SetVisibilityOn"}) do
        P(string.format("  槽%d Diplomacy.%-16s = %s", iProbe, n,
          try(function() return type(d[n]) end)))
      end
    end
    local ai = nil
    pcall(function() ai = p:GetDiplomaticAI() end)
    P("  槽"..iProbe.." GetDiplomaticAI() = "..try(function() return type(ai) end))
    if ai ~= nil then
      for _, n in ipairs({"GetDiplomaticStateIndex","GetDiplomaticState","GetAllDiplomaticStates"}) do
        P(string.format("    DiplomaticAI.%-24s = %s", n,
          try(function() return type(ai[n]) end)))
      end
    end
  end
else
  P("")
  P("  （本上下文没有 WorldBuilder，B 部分请用 --state GameCore_Tuner 跑）")
end
"""
    + EPILOGUE
)


# ---- 76. 静态查询：颜色是怎么分配的（表结构 + 新老玩家对比）----------------
PROBES["colorq"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 所有含 Color 的表 ==")
local r1 = nil
pcall(function()
  r1 = DB.ConfigurationQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND lower(name) LIKE '%color%'")
end)
if type(r1) == "table" then
  for _, row in ipairs(r1) do P("  "..tostring(row.name)) end
else
  P("  sqlite_master 查询不可用")
end

P("")
P("== 2. 新玩家(54) vs 原生城邦(6) 的颜色值 ==")
for _, id in ipairs({6, 54}) do
  local pc = PlayerConfigurations[id]
  if pc ~= nil then
    P(string.format("  槽%d civ=%s", id,
      try(function() return tostring(pc:GetCivilizationTypeName()) end)))
    P(string.format("      GetColor()=%s   GetPlayerName=%s",
      try(function() return tostring(pc:GetColor()) end),
      try(function() return tostring(pc:GetPlayerName()) end)))
  else
    P(string.format("  槽%d = nil", id))
  end
end

P("")
P("== 3. CivilizationColors 表（城邦文明的配色来源）==")
local r2 = nil
pcall(function()
  r2 = DB.ConfigurationQuery(
    "SELECT CivilizationType, ColorType, Usage FROM CivilizationColors LIMIT 30")
end)
if type(r2) == "table" then
  for _, row in ipairs(r2) do
    P(string.format("  %-34s %-26s %s", tostring(row.CivilizationType),
      tostring(row.ColorType), tostring(row.Usage)))
  end
  P("  （共 "..#r2.." 行）")
else
  P("  查询失败")
end

P("")
P("== 4. Leaders 表的颜色 InheritFrom（城邦颜色其实是继承来的）==")
local r3 = nil
pcall(function()
  r3 = DB.ConfigurationQuery(
    "SELECT LeaderType, InheritFrom FROM Leaders WHERE LeaderType LIKE 'LEADER_MINOR_CIV_%' LIMIT 12")
end)
if type(r3) == "table" then
  for _, row in ipairs(r3) do
    P(string.format("  %-40s -> %s", tostring(row.LeaderType), tostring(row.InheritFrom)))
  end
end
"""
    + EPILOGUE
)


# ---- 77. 最后线索：PlayerConfigurations:GetPlayerColorValues / GetColorChannels ----
PROBES["colorv"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== PlayerConfigurations 上的颜色相关方法（逐个试）==")
local tMethods = {"GetColor","GetPlayerColorValues","GetColorChannels","GetPlayerColors",
                  "GetPrimaryColor","GetSecondaryColor","GetColorValue"}
for _, id in ipairs({6, 54}) do
  local pc = PlayerConfigurations[id]
  if pc ~= nil then
    P("--- 槽 "..id.." ("..
      try(function() return tostring(pc:GetCivilizationTypeName()) end)..") ---")
    for _, m in ipairs(tMethods) do
      P(string.format("    %-22s = %s", m,
        try(function() return tostring(pc[m]) end)))
    end
  end
end

P("")
P("== UI 全局上的颜色接口逐个试（要求 UI 上下文）==")
local bHasUI = false
pcall(function() bHasUI = (type(UI) == "table") end)
if bHasUI then
  for _, m in ipairs({"GetPlayerColorValues","GetColorChannels","GetColors","GetColorValue"}) do
    P(string.format("    UI.%-22s = %s", m, try(function() return type(UI[m]) end)))
  end
  P("")
  P("  UI.GetPlayerColorValues(54) = "..
    try(function() return tostring(UI.GetPlayerColorValues(54)) end))
  P("  UI.GetPlayerColorValues(6)  = "..
    try(function() return tostring(UI.GetPlayerColorValues(6)) end))
  P("  UI.GetColorChannels(608547851) = "..
    try(function() return tostring(UI.GetColorChannels(608547851)) end))
else
  P("    （本上下文没有 UI 全局）")
end
"""
    + EPILOGUE
)


# ---- 78. ⭐ 正确调用 UI.GetPlayerColorValues（返回多值/表）------------------
PROBES["colorv2"] = (
    PRELUDE
    + r"""
P("  本上下文 UI 全局 = "..tostring(type(UI) ~= "nil"))

local function dumpCall(tag, fn, ...)
  local t = {pcall(fn, ...)}
  P("--- "..tag.." ---")
  P("   pcall ok = "..tostring(t[1]).."   返回个数 = "..tostring(#t - 1))
  for i = 2, #t do
    local v = t[i]
    P(string.format("   [%d] type=%s value=%s", i - 1, type(v), tostring(v)))
    if type(v) == "table" then
      for k, vv in pairs(v) do
        P(string.format("        %s = %s (%s)", tostring(k), tostring(vv), type(vv)))
      end
    end
  end
end

if type(UI) == "table" then
  dumpCall("UI.GetPlayerColorValues(54) 新玩家", UI.GetPlayerColorValues, 54)
  dumpCall("UI.GetPlayerColorValues(6)  原生城邦", UI.GetPlayerColorValues, 6)
  dumpCall("UI.GetPlayerColors(54)      新玩家", UI.GetPlayerColors, 54)
  dumpCall("UI.GetPlayerColors(6)       原生城邦", UI.GetPlayerColors, 6)
  dumpCall("UI.GetColors()              全表", UI.GetColors)
else
  P("  本上下文没有 UI 全局（请用 --state InGame）")
end
"""
    + EPILOGUE
)


# ---- 79. ⭐⭐⭐⭐⭐ 引擎自带判定：Plot:IsValidFoundLocation() ------------------
PROBES["foundcheck"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. Plot 上有没有 IsValidFoundLocation ==")
local pPlot = Map.GetPlot(10, 15)
P("  Map.GetPlot(10,15) = "..try(function() return type(pPlot) end))
if pPlot ~= nil then
  P("  pPlot.IsValidFoundLocation = "..try(function() return type(pPlot.IsValidFoundLocation) end))
  P("  直接调用（无参）      -> "..try(function() return tostring(pPlot:IsValidFoundLocation()) end))
  P("  带本地玩家 0          -> "..try(function() return tostring(pPlot:IsValidFoundLocation(0)) end))
end

P("")
P("== 2. 对比：已知好的格子 vs 已知坏的格子 ==")
-- (8,11) 之前成功过；(10,15) 一直失败
for _, xy in ipairs({{8,11},{10,15}}) do
  local p = Map.GetPlot(xy[1], xy[2])
  if p ~= nil then
    P(string.format("  (%d,%d): IsWater=%s GetOwner=%s  IsValidFoundLocation()=%s  (0)=%s",
      xy[1], xy[2],
      try(function() return tostring(p:IsWater()) end),
      try(function() return tostring(p:GetOwner()) end),
      try(function() return tostring(p:IsValidFoundLocation()) end),
      try(function() return tostring(p:IsValidFoundLocation(0)) end)))
  end
end

P("")
P("== 3. 扫描：引擎认为【可建城】的格子有多少、和我的判定差多少 ==")
local nEngine, nMine, nBoth, nOnlyEngine, nOnlyMine = 0, 0, 0, 0, 0
local fValid = nil; pcall(function() fValid = ExposedMembers.CSF.IsValidLocation end)
for x = 0, 80 do
  for y = 0, 60 do
    local p = Map.GetPlot(x, y)
    if p ~= nil then
      local e = false
      pcall(function() e = (p:IsValidFoundLocation() == true) end)
      local m = false
      if fValid ~= nil then
        local ok, b = pcall(fValid, x, y, 0)
        m = (ok and b == true)
      end
      if e then nEngine = nEngine + 1 end
      if m then nMine = nMine + 1 end
      if e and m then nBoth = nBoth + 1 end
      if e and not m then nOnlyEngine = nOnlyEngine + 1 end
      if m and not e then nOnlyMine = nOnlyMine + 1 end
    end
  end
end
P("  引擎认为可建 = "..nEngine)
P("  我的判定可建 = "..nMine)
P("  两者都同意   = "..nBoth)
P("  ⚠️ 只有引擎同意（我漏判）= "..nOnlyEngine)
P("  ⚠️⚠️ 只有我同意（引擎会拒绝 → Create 会静默失败！）= "..nOnlyMine)
"""
    + EPILOGUE
)


# ---- 80. ⭐⭐⭐⭐⭐ 规则探测：引擎在什么条件下接受 Create -------------------
#   用【动态创建的临时玩家】做实验 —— 它失败不会损坏本局任何城邦。
PROBES["ruleprobe"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

-- 找一个已有的城市作为参照点（任意玩家，含主文明）
local iRefX, iRefY = nil, nil
local tAll = {}
pcall(function()
  for _, id in ipairs(PlayerManager.GetAliveMajorIDs()) do tAll[#tAll+1] = id end
  for _, id in ipairs(PlayerManager.GetAliveMinorIDs()) do tAll[#tAll+1] = id end
end)
for _, id in ipairs(tAll) do
  if iRefX == nil then
    local n = 0; pcall(function() n = Players[id]:GetCities():GetCount() end)
    if n > 0 then
      pcall(function()
        for _, c in Players[id]:GetCities():Members() do
          if iRefX == nil then iRefX = c:GetX(); iRefY = c:GetY() end
        end
      end)
    end
  end
end
P("  参照城市坐标 = "..tostring(iRefX)..","..tostring(iRefY))

if iRefX == nil then
  P("  【中止】地图上还没有任何城市（回合太早），无法做距离实验")
else

P("")
P("== 逐个距离测试：在距参照城市 d 格的格子上 Create ==")
P("  （每次用一个【全新的临时玩家】，避免互相干扰）")
P("  距离 | 坐标 | IsWater | Owner | 相邻陆地 | Create结果")

for iDist = 1, 8 do
  -- 沿 X 轴找距参照城市 iDist 的格
  local tx, ty = iRefX + iDist, iRefY
  local p = Map.GetPlot(tx, ty)
  if p == nil then
    P(string.format("  %d | (%d,%d) | 无此格", iDist, tx, ty))
  else
    local w = try(function() return tostring(p:IsWater()) end)
    local o = try(function() return tostring(p:GetOwner()) end)
    local land = 0
    for _, k in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
      local pn = Map.GetPlot(tx + k[1], ty + k[2])
      if pn ~= nil then
        local bw = false
        pcall(function() bw = pn:IsWater() end)
        if not bw then land = land + 1 end
      end
    end

    -- 造一个临时玩家
    local iTmp = nil
    pcall(function() iTmp = pm:AddPlayer(true) end)
    local sRes = "n/a"
    if iTmp ~= nil and iTmp ~= -1 then
      local sLdr = nil
      pcall(function()
        for row in GameInfo.CivilizationLeaders() do
          if row.CivilizationType == "CIVILIZATION_AKKAD" then sLdr = row.LeaderType end
        end
      end)
      if sLdr ~= nil then
        pcall(function() pm:SetPlayerLeader(iTmp, sLdr, "CIVILIZATION_AKKAD", "CIVILIZATION_LEVEL_CITY_STATE") end)
        pcall(function() pm:SetRandomMinorStartingPosition(iTmp) end)
        local iB = 0
        pcall(function() iB = Players[iTmp]:GetCities():GetCount() end)
        pcall(function() Players[iTmp]:GetCities():Create(tx, ty) end)
        local iA = 0
        pcall(function() iA = Players[iTmp]:GetCities():GetCount() end)
        sRes = (iA > iB) and "✅成功" or "❌失败"
      end
    else
      sRes = "无空槽"
    end
    P(string.format("  %d | (%d,%d) | %s | %s | %d | %s", iDist, tx, ty, w, o, land, sRes))
  end
end

P("")
P("  ⭐ 结论：找出【最小成功距离】与【相邻陆地要求】")
end
end
"""
    + EPILOGUE
)


# ---- 81. ⭐⭐⭐⭐⭐ 新思路：让城邦【自己去建】—— 放置移民而非 Create --------
#   动机：`Create` 在间距不足时会【静默失败并损坏城邦】。若改为"把城邦的移民
#   放到指定格，让它自己的 AI 建城"，则建城由引擎完成 —— 不会失败、不会损坏。
PROBES["settler"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then P("【中止】WorldBuilder 不可用") else

P("== 0. PlayerManager 上的位置相关方法 ==")
for _, m in ipairs({"SetPlayerStartingPosition","SetRandomMinorStartingPosition",
                    "GetPlayerConfig","SetPlayerSlotStatus"}) do
  P(string.format("  %-32s = %s", m, try(function() return type(pm[m]) end)))
end

P("")
P("== 1. 找一个休眠城邦（0 城）==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iTarget = nil
for _, id in ipairs(tIDs) do
  local n = 0; pcall(function() n = Players[id]:GetCities():GetCount() end)
  if n == 0 and iTarget == nil then iTarget = id end
end
P("  目标槽 = "..tostring(iTarget))

if iTarget == nil then
  P("  【中止】没有休眠城邦")
else
  -- 找一个远离现有城市的空地（距离 >= 8，确保引擎会接受）
  local tCities = {}
  for _, id in ipairs(tIDs) do
    local n = 0; pcall(function() n = Players[id]:GetCities():GetCount() end)
    if n > 0 then
      pcall(function()
        for _, c in Players[id]:GetCities():Members() do
          tCities[#tCities+1] = {c:GetX(), c:GetY()}
        end
      end)
    end
  end
  pcall(function()
    for _, id in ipairs(PlayerManager.GetAliveMajorIDs()) do
      for _, c in Players[id]:GetCities():Members() do
        tCities[#tCities+1] = {c:GetX(), c:GetY()}
      end
    end
  end)
  P("  地图上已有城市 = "..#tCities.." 座")

  local spot = nil
  for x = 3, 77 do
    for y = 3, 57 do
      local p = Map.GetPlot(x, y)
      if p ~= nil then
        local w = false; pcall(function() w = p:IsWater() end)
        local o = -1;  pcall(function() o = p:GetOwner() end)
        if not w and o == -1 then
          local okAll = true
          for _, c in ipairs(tCities) do
            local d = Map.GetPlotDistance(x, y, c[1], c[2])
            if d ~= nil and d < 8 then okAll = false; break end
          end
          if okAll then spot = {x, y}; break end
        end
      end
    end
    if spot ~= nil then break end
  end

  if spot == nil then
    P("  【跳过】找不到足够远的空地")
  else
    P(string.format("  选定位置 = (%d,%d)", spot[1], spot[2]))

    P("")
    P("== 2. 把该城邦的移民放到这个格子上 ==")
    P("  （不再调用 Cities:Create，让城邦自己建）")
    local bInit = pcall(function()
      UnitManager.InitUnit(iTarget, "UNIT_SETTLER", spot[1], spot[2])
    end)
    P("  InitUnit ok="..tostring(bInit))

    -- 立刻查它有没有单位、在哪
    local tUnits = {}
    pcall(function()
      for _, u in Players[iTarget]:GetUnits():Members() do
        tUnits[#tUnits+1] = string.format("%s@(%s,%s)",
          try(function() return tostring(GameInfo.Units[u:GetType()].UnitType) end),
          try(function() return tostring(u:GetX()) end),
          try(function() return tostring(u:GetY()) end))
      end
    end)
    P("  该城邦现有单位 = "..(#tUnits > 0 and table.concat(tUnits, ", ") or "无"))

    P("")
    P("== 3. 下次自检：等 1 回合看它是否自行建城 ==")
    P("  （若城邦 AI 会自己建城 → 这条路可行，且不会失败/损坏）")
  end
end
end
"""
    + EPILOGUE
)


# ---- 82. ⭐⭐⭐⭐⭐ 验证「建邦后不再重复出现」（T-124）------------------------
PROBES["dedupe"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local fGet   = nil; pcall(function() fGet   = ExposedMembers.CSF.GetFoundableCityStates end)
local fFound = nil; pcall(function() fFound = ExposedMembers.CSF.FoundCityStateByCiv end)

local function reuseCivs()
  local t = {}
  local ok, a = pcall(fGet)
  if ok and type(a) == "table" then
    for _, e in ipairs(a) do
      if e.Mode == "reuse" then t[#t+1] = e.Civ end
    end
  end
  return t
end

local iMe = Game.GetLocalPlayer()

P("== 1. 建邦前的可选列表 ==")
local tBefore = reuseCivs()
P("  可建城邦 = "..#tBefore.." 个")
for i, c in ipairs(tBefore) do
  if i <= 6 then P("    "..i..". "..c) end
end

if #tBefore == 0 then
  P("  【中止】没有可建城邦")
else
  local sTarget = tBefore[1]
  P("")
  P("== 2. 建立 "..sTarget.." ==")

  local tCities = {}
  local tAll = {}
  pcall(function()
    for _, id in ipairs(PlayerManager.GetAliveMajorIDs()) do tAll[#tAll+1] = id end
    for _, id in ipairs(PlayerManager.GetAliveMinorIDs()) do tAll[#tAll+1] = id end
  end)
  for _, id in ipairs(tAll) do
    pcall(function()
      for _, c in Players[id]:GetCities():Members() do
        tCities[#tCities+1] = {c:GetX(), c:GetY()}
      end
    end)
  end
  local spot = nil
  for x = 3, 77 do
    for y = 3, 57 do
      local p = Map.GetPlot(x, y)
      if p ~= nil and spot == nil then
        local w = false; pcall(function() w = p:IsWater() end)
        local o = -1;  pcall(function() o = p:GetOwner() end)
        if not w and o == -1 then
          local okAll = true
          for _, c in ipairs(tCities) do
            local d = Map.GetPlotDistance(x, y, c[1], c[2])
            if d ~= nil and d < 8 then okAll = false; break end
          end
          if okAll then spot = {x, y} end
        end
      end
    end
    if spot ~= nil then break end
  end
  P("  地点 = "..tostring(spot and spot[1])..","..tostring(spot and spot[2]))

  if spot ~= nil then
    local iUnitID = nil
    pcall(function()
      local u = UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", spot[1], spot[2])
      if u ~= nil then iUnitID = u:GetID() end
    end)
    local ok, bOk, sReason, iCs = pcall(fFound, sTarget, spot[1], spot[2], iUnitID, iMe)
    P("  建邦 -> ok="..tostring(ok).." bOk="..tostring(bOk)..
      " reason="..tostring(sReason).." player="..tostring(iCs))

    P("")
    P("== 3. 建邦后的可选列表（"..sTarget.." 应已消失）==")
    local tAfter = reuseCivs()
    P("  可建城邦 = "..#tAfter.." 个（建邦前 "..#tBefore.." 个）")

    local bStill = false
    for _, c in ipairs(tAfter) do
      if c == sTarget then bStill = true end
    end
    P("")
    if bStill then
      P("  ❌❌ 失败："..sTarget.." 仍在可选列表里 —— 还能被重复选择！")
    else
      P("  ✅✅ 通过："..sTarget.." 已从可选列表移除，无法重复选择")
    end

    if iCs ~= nil and iCs >= 0 then
      P("")
      P("  城邦玩家 "..tostring(iCs).." 现状：")
      P("     cities = "..try(function() return tostring(Players[iCs]:GetCities():GetCount()) end))
      local nOnMap, nOffMap = 0, 0
      pcall(function()
        for _, u in Players[iCs]:GetUnits():Members() do
          local x = u:GetX()
          if x ~= nil and x >= 0 then nOnMap = nOnMap + 1 else nOffMap = nOffMap + 1 end
        end
      end)
      P("     地图上单位 = "..nOnMap.."，地图外单位 = "..nOffMap)
    end
  end
end
"""
    + EPILOGUE
)


# ---- 83. ⭐⭐⭐⭐⭐ 在 CSF_Panel 自己的上下文里自检面板 ------------------------
PROBES["panelctx"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,50)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 上下文与关键控件是否存在 ==")
P("  ContextPtr:GetName() = "..try(function() return ContextPtr:GetName() end))
P("  CSF_Open 存在        = "..tostring(CSF_Open ~= nil))
for _, n in ipairs({"CSFRoot","CSFWindow","CSFAnimIn","CSFAnimSlide","CSFTitle","CSFHint",
                    "CSFCityStateScroll","CSFCityStateStack","CSFSelectedName","CSFSelectedBonus",
                    "CSFConfirmButton","CSFCancelButton","CSFCloseButton"}) do
  local c = nil
  pcall(function() c = Controls[n] end)
  P(string.format("  %-22s = %s", n, tostring(c ~= nil)))
end

P("")
P("== 2. 打开前的状态 ==")
P("  CSFRoot:IsHidden() = "..try(function() return tostring(Controls.CSFRoot:IsHidden()) end))

P("")
P("== 3. 调 CSF_Open() ==")
local ok = pcall(function() CSF_Open() end)
P("  CSF_Open() ok = "..tostring(ok))

P("")
P("== 4. 打开后的状态（关键：面板必须可见）==")
P("  CSFRoot:IsHidden()    = "..try(function() return tostring(Controls.CSFRoot:IsHidden()) end))
P("  CSFRoot 尺寸          = "..try(function()
  return tostring(Controls.CSFRoot:GetSizeX()).."x"..tostring(Controls.CSFRoot:GetSizeY())
end))
P("  CSFWindow:IsHidden()  = "..try(function() return tostring(Controls.CSFWindow:IsHidden()) end))
P("  CSFWindow 尺寸/位置   = "..try(function()
  return tostring(Controls.CSFWindow:GetSizeX()).."x"..tostring(Controls.CSFWindow:GetSizeY())
end).." @ "..try(function()
  local x, y = Controls.CSFWindow:GetScreenOffset();
  return tostring(x)..","..tostring(y)
end))
P("  CSFAnimIn:IsHidden()  = "..try(function() return tostring(Controls.CSFAnimIn:IsHidden()) end))
P("  CSFAnimIn 尺寸        = "..try(function()
  return tostring(Controls.CSFAnimIn:GetSizeX()).."x"..tostring(Controls.CSFAnimIn:GetSizeY())
end))
P("  CSFTitle 文本         = "..try(function() return tostring(Controls.CSFTitle:GetText()) end))
P("  CSFHint 文本          = "..try(function() return tostring(Controls.CSFHint:GetText()) end))
P("  CSFConfirmButton 文本 = "..try(function() return tostring(Controls.CSFConfirmButton:GetText()) end))

P("")
P("== 5. 列表条目数 ==")
local n = 0
pcall(function() n = Controls.CSFCityStateStack:GetNumChildren() end)
P("  CSFCityStateStack 子控件 = "..tostring(n))
"""
    + EPILOGUE
)


# ---- 84. ⭐⭐⭐⭐⭐ 实测列表几何：为什么条目溢出 -------------------------------
PROBES["listgeom"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function geom(c, tag)
  if c == nil then P("  "..tag.." = nil"); return end
  P(string.format("  %-22s size=%-12s @ %-12s hidden=%s",
    tag,
    try(function() return tostring(c:GetSizeX()).."x"..tostring(c:GetSizeY()) end),
    try(function() local x,y = c:GetScreenOffset(); return tostring(x)..","..tostring(y) end),
    try(function() return tostring(c:IsHidden()) end)))
end

P("== 1. 先打开面板 ==")
pcall(function() CSF_Open() end)
P("  CSF_Open 调用完毕")

P("")
P("== 2. 关键容器的真实几何 ==")
geom(Controls.CSFRoot,          "CSFRoot")
geom(Controls.CSFWindow,        "CSFWindow")
geom(Controls.CSFHint,          "CSFHint")
geom(Controls.CSFCityStateScroll,"ScrollPanel")
geom(Controls.CSFCityStateStack, "Stack")
geom(Controls.CSFConfirmButton,  "ConfirmButton")
geom(Controls.CSFCancelButton,   "CancelButton")
geom(Controls.CSFSelectedName,   "SelectedName")

P("")
P("== 3. 列表条目的真实几何（看是否溢出 ScrollPanel）==")
local n = 0
pcall(function() n = Controls.CSFCityStateStack:GetNumChildren() end)
P("  Stack 子控件数 = "..tostring(n))
local i = 0
pcall(function()
  for _, child in ipairs(Controls.CSFCityStateStack:GetChildren()) do
    i = i + 1
    if i <= 3 or i >= n - 1 then
      geom(child, "条目 "..i)
    end
  end
end)

P("")
P("== 4. 判断 ==")
local sc = Controls.CSFCityStateScroll
local st = Controls.CSFCityStateStack
if sc ~= nil and st ~= nil then
  local sh = nil; pcall(function() sh = sc:GetSizeY() end)
  local th = nil; pcall(function() th = st:GetSizeY() end)
  P("  ScrollPanel 高 = "..tostring(sh))
  P("  Stack 高       = "..tostring(th))
  if sh ~= nil and th ~= nil then
    if th > sh then
      P("  ⚠️ 内容("..tostring(th)..") > 视口("..tostring(sh)..") —— 若界面里溢出，说明 ScrollPanel 未裁剪")
    else
      P("  ✅ 内容未超出视口")
    end
  end
end
"""
    + EPILOGUE
)


# ---- 85. 自检用：探控件有哪些运行时 setter，并把面板挪进可见区 -----------------
PROBES["shiftpanel"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 控件上有哪些 setter（探测）==")
local c = Controls.CSFWindow
for _, m in ipairs({"SetOffsetY","SetOffsetX","SetOffset","SetSizeY","SetSizeX","SetSize",
                    "SetHide","SetAlpha","SetPosition","SetScreenOffset"}) do
  P(string.format("  %-18s = %s", m, try(function() return type(c[m]) end)))
end

P("")
P("== 2. 屏幕与 UI 空间尺寸 ==")
P("  UI 空间 = "..try(function() return tostring(UI.GetScreenSize()) end))
P("  ContextPtr 尺寸 = "..try(function()
  return tostring(ContextPtr:GetSizeX()).."x"..tostring(ContextPtr:GetSizeY())
end))
P("  CSFRoot 尺寸 = "..try(function()
  return tostring(Controls.CSFRoot:GetSizeX()).."x"..tostring(Controls.CSFRoot:GetSizeY())
end))

P("")
P("== 3. 尝试把 CSFWindow 上移（逐个试，记录哪个成功）==")
local bMoved = false
for _, m in ipairs({"SetOffsetY","SetOffset"}) do
  local f = nil; pcall(function() f = c[m] end)
  if type(f) == "function" then
    local ok = pcall(function()
      if m == "SetOffsetY" then c:SetOffsetY(-280)
      else c:SetOffset(363, -140) end
    end);
    P("  "..m.." -> ok="..tostring(ok));
    if ok then bMoved = true; break end
  end
end
if not bMoved then
  -- 退路：把 SlideAnim 的 End 改掉（SlideAnim 有 SetEnd？）——先看有没有
  P("  直接移动失败，改试 SlideAnim：")
  local a = Controls.CSFAnimSlide
  for _, m in ipairs({"SetEnd","SetToEnd","SetBegin"}) do
    P(string.format("    SlideAnim.%-10s = %s", m, try(function() return type(a[m]) end)))
  end
  pcall(function() a:SetToEnd() end);
  P("    SetToEnd() 调用后 CSFWindow @ "..try(function()
    local x,y = Controls.CSFWindow:GetScreenOffset(); return tostring(x)..","..tostring(y)
  end))
end

P("")
P("== 4. 挪动后的坐标 ==")
P("  CSFWindow @ "..try(function()
  local x,y = Controls.CSFWindow:GetScreenOffset(); return tostring(x)..","..tostring(y)
end))
for _, n in ipairs({"CSFCityStateClip","CSFCityStateScroll","CSFSelectedName","CSFConfirmButton"}) do
  local cc = nil; pcall(function() cc = Controls[n] end)
  if cc ~= nil then
    P(string.format("  %-20s @ %s", n, try(function()
      local x,y = cc:GetScreenOffset(); return tostring(x)..","..tostring(y)
    end)))
  end
end
"""
    + EPILOGUE
)


# ---- 86. ⭐⭐⭐⭐⭐ 全链路几何：找出"谁溢出了玻璃窗" -------------------------
PROBES["chain"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,40)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function g(c, tag)
  if c == nil then P(string.format("  %-24s = nil", tag)); return end
  local x, y, sx, sy = nil, nil, nil, nil
  pcall(function() x, y = c:GetScreenOffset() end)
  pcall(function() sx = c:GetSizeX(); sy = c:GetSizeY() end)
  P(string.format("  %-24s %5sx%-5s  x %5s..%-5s   y %5s..%-5s",
    tag, tostring(sx), tostring(sy), tostring(x), tostring(x and sx and (x+sx)),
    tostring(y), tostring(y and sy and (y+sy))))
end

P("== 1. 恢复面板位置（清掉我自检时的 SetOffsetY）==")
pcall(function() Controls.CSFWindow:SetOffsetY(0) end)
pcall(function() Controls.CSFWindow:SetOffsetX(0) end)
P("  CSFWindow @ "..try(function()
  local x,y = Controls.CSFWindow:GetScreenOffset(); return tostring(x)..","..tostring(y)
end))

P("")
P("== 2. 从外到内的横向链路（看哪一层开始超出）==")
g(Controls.CSFRoot,           "CSFRoot(全屏)")
g(Controls.CSFWindow,         "CSFWindow")
g(Controls.CSFListGlass,      "  ListGlass")
g(Controls.CSFCityStateClip,  "    Clip(Group)")
g(Controls.CSFCityStateScroll,"    ScrollPanel")
g(Controls.CSFCityStateStack, "    Stack")

P("")
P("== 3. 条目与条目内的文字 ==")
local n = 0
pcall(function() n = Controls.CSFCityStateStack:GetNumChildren() end)
P("  条目数 = "..tostring(n))
local i = 0
pcall(function()
  for _, child in ipairs(Controls.CSFCityStateStack:GetChildren()) do
    i = i + 1
    if i == 1 then
      g(child, "  条目1(按钮)")
      pcall(function()
        for _, sub in ipairs(child:GetChildren()) do
          local sid = nil
          pcall(function() sid = sub:GetID() end)
          if sid ~= nil and sid:find("Bonus") then g(sub, "    "..sid) end
          if sid ~= nil and sid:find("Name")  then g(sub, "    "..sid) end
        end
      end)
    end
  end
end)

P("")
P("== 4. 结论：谁越过了 CSFWindow 的右边界 ==")
local wx, wsx = nil, nil
pcall(function() wx = Controls.CSFWindow:GetScreenOffset(); wsx = Controls.CSFWindow:GetSizeX() end)
if wx ~= nil and wsx ~= nil then
  local right = wx + wsx
  P("  CSFWindow 右边界 = "..tostring(right))
  for _, k in ipairs({{"ListGlass", Controls.CSFListGlass},
                      {"Clip", Controls.CSFCityStateClip},
                      {"ScrollPanel", Controls.CSFCityStateScroll},
                      {"Stack", Controls.CSFCityStateStack}}) do
    local x, sx = nil, nil
    pcall(function() x = k[2]:GetScreenOffset(); sx = k[2]:GetSizeX() end)
    if x ~= nil and sx ~= nil then
      local r = x + sx
      P(string.format("  %-14s 右边界 %-6s %s", k[1], tostring(r),
        (r > right) and "⚠️ 超出玻璃窗！" or "✅ 在内"))
    end
  end
end
"""
    + EPILOGUE
)


# ---- 87. 自检用：把面板临时位移，让屏幕外的部分进入视野（不改文件）------------
PROBES["shift"] = (
    PRELUDE
    + r"""
local tArgs = { ... };
local iDx = -330;
local iDy = -120;

P("== 位移面板（仅本次运行，重启即恢复）==")
pcall(function() CSF_Open() end);          -- 先确保面板是打开的
P("  CSF_Open 已调用")
P("  之前 @ "..tostring(select(1, Controls.CSFWindow:GetScreenOffset()))..","..
              tostring(select(2, Controls.CSFWindow:GetScreenOffset())))
local ok1 = pcall(function() Controls.CSFWindow:SetOffsetX(iDx) end);
local ok2 = pcall(function() Controls.CSFWindow:SetOffsetY(iDy) end);
P("  SetOffsetX("..iDx..") ok="..tostring(ok1))
P("  SetOffsetY("..iDy..") ok="..tostring(ok2))
local x, y = Controls.CSFWindow:GetScreenOffset();
P("  之后 @ "..tostring(x)..","..tostring(y))

P("")
P("== 位移后各层横向边界 ==")
local function g(c, tag)
  if c == nil then return end
  local cx, csx = nil, nil
  pcall(function() cx = c:GetScreenOffset(); csx = c:GetSizeX() end)
  if cx ~= nil and csx ~= nil then
    P(string.format("  %-22s x %5s..%-5s", tag, tostring(cx), tostring(cx + csx)))
  end
end
g(Controls.CSFWindow,        "CSFWindow")
g(Controls.CSFListGlass,     "  ListGlass")
g(Controls.CSFCityStateClip, "    Clip")
local n = 0; pcall(function() n = Controls.CSFCityStateStack:GetNumChildren() end)
local i = 0
pcall(function()
  for _, child in ipairs(Controls.CSFCityStateStack:GetChildren()) do
    i = i + 1
    if i == 1 then
      g(child, "    条目1")
      pcall(function()
        for _, sub in ipairs(child:GetChildren()) do
          local sid = nil; pcall(function() sid = sub:GetID() end)
          if sid ~= nil and (sid:find("Bonus") or sid:find("Name")) then g(sub, "      "..sid) end
        end
      end)
    end
  end
end)
"""
    + EPILOGUE
)


# ---- 88. ⭐⭐⭐⭐⭐ 核实单位改动是否真的进了玩法库（T-140 / T-141）-------------
PROBES["unitcheck"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR("..tostring(v):sub(1,45)..")" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. Units 行（FoundCity 必须是 false、PseudoYieldType 必须为空）==")
local u = GameInfo.Units["UNIT_CSF_ENVOY"]
if u == nil then
  P("  ❌ GameInfo.Units['UNIT_CSF_ENVOY'] 不存在！")
else
  P("  FoundCity       = "..tostring(u.FoundCity).."      （期望 false）")
  P("  PseudoYieldType = "..try(function() return tostring(u.PseudoYieldType) end).."      （期望 nil）")
  P("  Cost            = "..tostring(u.Cost))
  P("  Domain          = "..tostring(u.Domain))
  P("  FormationClass  = "..tostring(u.FormationClass))
  P("  CanTrain        = "..tostring(u.CanTrain))
  P("  TraitType       = "..try(function() return tostring(u.TraitType) end))
end

P("")
P("== 2. UnitAiInfos（必须【没有】UNITAI_SETTLE）==")
local nAi, tAi = 0, {}
local okAi = pcall(function()
  for row in GameInfo.UnitAiInfos() do
    if row.UnitType == "UNIT_CSF_ENVOY" then
      nAi = nAi + 1
      tAi[#tAi+1] = row.AiType
    end
  end
end)
if okAi then
  P("  共 "..nAi.." 条："..(#tAi > 0 and table.concat(tAi, ", ") or "（无）"))
  local bHasSettle = false
  for _, a in ipairs(tAi) do if a == "UNITAI_SETTLE" then bHasSettle = true end end
  P("  ⭐ 含 UNITAI_SETTLE = "..tostring(bHasSettle).."   （必须为 false —— 否则 AI 会造它）")
else
  P("  GameInfo.UnitAiInfos 查询失败")
end

P("")
P("== 3. 图标定义（T-141：应全部指向开拓者那一格）==")
P("  ⚠️ 图标在【UI 库】，GameCore 上下文读不到 GameInfo.Icons —— 需用 --state InGame 跑")
local tIcons = {
  "ICON_UNIT_CSF_ENVOY", "ICON_UNIT_CSF_ENVOY_FOW",
  "ICON_UNIT_CSF_ENVOY_WHITE", "ICON_UNIT_CSF_ENVOY_BLACK",
  "ICON_UNIT_CSF_ENVOY_PORTRAIT", "ICON_UNIT_CSF_ENVOY_PORTRAIT_ERA_MODERN",
  "ICON_UNIT_CSF_ENVOY_PORTRAIT_ERA_ATOMIC", "ICON_UNIT_CSF_ENVOY_PORTRAIT_ERA_INFORMATION",
}
local tIconsTbl = nil
pcall(function() tIconsTbl = GameInfo.Icons end)
if tIconsTbl == nil then
  P("  （本上下文无 GameInfo.Icons，跳过）")
else
  for _, nm in ipairs(tIcons) do
    local r = nil
    pcall(function() r = tIconsTbl[nm] end)
    if r == nil then
      P(string.format("  ❌ %-46s 未找到", nm))
    else
      P(string.format("  ✅ %-46s Atlas=%s Index=%s",
        nm, tostring(r.Atlas), tostring(r.Index)))
    end
  end
  P("")
  P("  对照：开拓者本身")
  for _, nm in ipairs({"ICON_UNIT_SETTLER","ICON_UNIT_SETTLER_PORTRAIT_ERA_MODERN"}) do
    local r = nil
    pcall(function() r = tIconsTbl[nm] end)
    if r ~= nil then
      P(string.format("  %-46s Atlas=%s Index=%s", nm, tostring(r.Atlas), tostring(r.Index)))
    end
  end
end

P("")
P("== 5. Units_XP2.MajorCivOnly（城邦/蛮族不能造）==")
local x = nil
pcall(function() x = GameInfo.Units_XP2["UNIT_CSF_ENVOY"] end)
if x ~= nil then
  P("  MajorCivOnly = "..tostring(x.MajorCivOnly).."   （期望 true）")
else
  P("  ⚠️ 读不到 Units_XP2 行（可能本上下文无该表）")
end
"""
    + EPILOGUE
)


# ---- 89. ⭐⭐⭐⭐⭐ 路线 C 实测：额外休眠城邦（T-144）--------------------------
PROBES["extraprobe"] = (
    PRELUDE
    + r"""
local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR" end
  if v == nil then return "nil" end
  return tostring(v)
end

P("== 1. 本局城邦玩家总数（期望 = 开局设置数 + 额外数）==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  GetAliveMinorIDs 返回 "..#tIDs.." 个")

P("")
P("== 2. 逐个体检：ID / 文明 / 城数 / 地图上单位数 / 是否预留 ==")
local nDormant, nActive = 0, 0
for _, id in ipairs(tIDs) do
  local sCiv = "?"
  pcall(function() sCiv = tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end)
  local iC = 0
  pcall(function() iC = Players[id]:GetCities():GetCount() end)
  local iOnMap = 0
  pcall(function()
    for _, u in Players[id]:GetUnits():Members() do
      local x, y = u:GetX(), u:GetY()
      if x ~= nil and y ~= nil and x >= 0 and y >= 0 then iOnMap = iOnMap + 1 end
    end
  end)
  local bAlive = false
  pcall(function() bAlive = Players[id]:IsAlive() end)
  local mark = "  "
  if iC == 0 and iOnMap == 0 then nDormant = nDormant + 1; mark = "💤"
  elseif iC > 0 then nActive = nActive + 1; mark = "🏛️" end
  P(string.format("  %s id=%-3s %-42s cities=%s onMap=%s alive=%s",
    mark, tostring(id), sCiv, tostring(iC), tostring(iOnMap), tostring(bAlive)))
end
P("  ── 小结：已建城 "..nActive.." 座，休眠 "..nDormant.." 座")

P("")
P("== 3. 高位槽（54-61）占用情况 —— AddPlayer 会拿这些 ==")
for slot = 50, 63 do
  local st = nil
  pcall(function()
    local pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager()
    if pm ~= nil then st = pm:GetSlotStatus(slot) end
  end)
  local sCiv = "?"
  pcall(function() sCiv = tostring(PlayerConfigurations[slot]:GetCivilizationTypeName()) end)
  if st ~= nil or (sCiv ~= "?" and sCiv ~= "nil") then
    P(string.format("  slot %-3s status=%-6s civ=%s", tostring(slot), tostring(st), sCiv))
  end
end

P("")
P("== 4. 面板实际会列出的数量（reuse 口径）==")
local nFoundable = 0
for _, id in ipairs(tIDs) do
  local iC = 0
  pcall(function() iC = Players[id]:GetCities():GetCount() end)
  if iC == 0 then
    local bOnMap = false
    pcall(function()
      for _, u in Players[id]:GetUnits():Members() do
        local x, y = u:GetX(), u:GetY()
        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then bOnMap = true break end
      end
    end)
    if not bOnMap then nFoundable = nFoundable + 1 end
  end
end
P("  ⭐ 可建城邦 = "..nFoundable.." 个")
"""
    + EPILOGUE
)


# ---- 90. ⭐⭐⭐⭐⭐ 颜色检查（必须在 InGame / UI 上下文跑）--------------------
PROBES["colorprobe"] = (
    PRELUDE
    + r"""
P("== UI.GetPlayerColors 逐个查（路线 C 最大风险点）==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local nOk, nNil = 0, 0
for _, id in ipairs(tIDs) do
  local sCiv = "?"
  pcall(function() sCiv = tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end)
  local c1, c2 = nil, nil
  pcall(function() c1, c2 = UI.GetPlayerColors(id) end)
  if c1 == nil then
    nNil = nNil + 1
    P(string.format("  ❌ id=%-3s %-42s  GetPlayerColors = nil", tostring(id), sCiv))
  else
    nOk = nOk + 1
    P(string.format("  ✅ id=%-3s %-42s  color=%s", tostring(id), sCiv, tostring(c1)))
  end
end
P("  ── 有颜色 "..nOk.." 个，取不到 "..nNil.." 个")
if nNil > 0 then
  P("  ⚠️ 取不到颜色的就是 AddPlayer 新建的高位槽 —— 路线 C 的核心障碍")
else
  P("  🎉 全部都能取到颜色 —— 路线 C 可行！")
end
"""
    + EPILOGUE
)


# ---- 91. ⭐⭐⭐⭐⭐ 验收：实际建一个【额外城邦】并检查结果（T-144）----------
#   ⚠️ 本探针体用 pcall 包裹 —— 因为 PRELUDE/EPILOGUE 是"最后统一 print(OUT)"，
#      中途一出错就完全没输出。包起来才能看到"出错前收集到的内容 + 错误信息"。
PROBES["foundextra"] = (
    PRELUDE
    + r"""
local okBody, errBody = pcall(function()

local CSF = ExposedMembers and ExposedMembers.CSF
P("== 0. ExposedMembers.CSF = "..tostring(CSF ~= nil).." ==")
if CSF == nil then P("❌ 不可用（GameCore 上下文可能没有 ExposedMembers）") return end

local sCiv = "CIVILIZATION_ANTIOCH"
local iMe  = Game.GetLocalPlayer()
P("  本地玩家 = "..tostring(iMe))

P("== 1. 找 ANTIOCH 的休眠玩家 ==")
local iTarget = nil
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local s = nil
  pcall(function() s = PlayerConfigurations[id]:GetCivilizationTypeName() end)
  if s == sCiv then iTarget = id end
end
P("  目标玩家 ID = "..tostring(iTarget))
if iTarget == nil then P("❌ 本局没有 ANTIOCH") return end

P("== 2. 找一个合法建邦位置 ==")
local iX, iY = nil, nil
pcall(function()
  local ux, uy = nil, nil
  for _, u in Players[iMe]:GetUnits():Members() do
    local x, y = u:GetX(), u:GetY()
    if x ~= nil and y ~= nil and x >= 0 and y >= 0 then ux, uy = x, y break end
  end
  P("  参考单位在 ("..tostring(ux)..","..tostring(uy)..")")
  if ux == nil then return end
  for r = 1, 10 do
    for dx = -r, r do
      for dy = -r, r do
        if iX == nil then
          local x, y = ux + dx, uy + dy
          local bOk = false
          pcall(function()
            if Map.GetPlot(x, y) ~= nil then bOk = CSF.IsValidLocation(x, y, iMe) end
          end)
          if bOk then iX, iY = x, y end
        end
      end
    end
    if iX ~= nil then break end
  end
end)
P("  选定位置 = ("..tostring(iX)..","..tostring(iY)..")")
if iX == nil then P("❌ 没找到合法位置") return end

P("== 3. 调用 FoundCityStateByCiv ==")
local ok, reason, pid, bFull = CSF.FoundCityStateByCiv(sCiv, iX, iY, nil, iMe)
P("  ok="..tostring(ok).."  reason="..tostring(reason)..
  "  playerID="..tostring(pid).."  fullMechanics="..tostring(bFull))

P("== 4. 该玩家现在的单位 ==")
pcall(function()
  local n = 0
  for _, u in Players[iTarget]:GetUnits():Members() do
    n = n + 1
    P("    type="..tostring(GameInfo.Units[u:GetType()].UnitType)..
      " at ("..tostring(u:GetX())..","..tostring(u:GetY())..")")
  end
  P("  单位数 = "..n)
end)

P("== 5. 当前城数（应仍为 0，等它的回合）==")
local c = 0
pcall(function() c = Players[iTarget]:GetCities():GetCount() end)
P("  cities = "..c)

end)
if not okBody then P("❌❌ 探针体出错："..tostring(errBody)) end
"""
    + EPILOGUE
)


# ---- 92. ⭐⭐⭐⭐⭐ 复查建出来的额外城邦（T-144）------------------------------
PROBES["citycheck"] = (
    PRELUDE
    + r"""
P("== 额外城邦的最终状态 ==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  local sCiv = "?"
  pcall(function() sCiv = tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end)
  local iC = 0
  pcall(function() iC = Players[id]:GetCities():GetCount() end)
  if iC > 0 then
    local cityName, pop, owner = "?", 0, id
    pcall(function()
      for city in Players[id]:GetCities():Members() do
        cityName = Locale.Lookup(city:GetName())
        pop = city:GetPopulation()
      end
    end)
    local isCS = "?"
    pcall(function() isCS = tostring(Players[id]:IsMinorCiv()) end)
    local suz = "?"
    pcall(function() suz = tostring(Players[id]:GetInfluence():GetSuzerain() ) end)
    P(string.format("  id=%-3s %-34s 城市=%-16s 人口=%s isMinor=%s suzerain=%s",
      tostring(id), sCiv, cityName, tostring(pop), isCS, suz))
  end
end

P("")
P("== 全部城邦（含未建城的）==")
local nActive, nDorm = 0, 0
for _, id in ipairs(tIDs) do
  local sCiv = "?"
  pcall(function() sCiv = tostring(PlayerConfigurations[id]:GetCivilizationTypeName()) end)
  local iC = 0
  pcall(function() iC = Players[id]:GetCities():GetCount() end)
  local bAlive = false
  pcall(function() bAlive = Players[id]:IsAlive() end)
  if iC > 0 then nActive = nActive + 1 else nDorm = nDorm + 1 end
  P(string.format("  %s id=%-3s %-36s cities=%s alive=%s",
    (iC > 0 and "🏛️" or "💤"), tostring(id), sCiv, tostring(iC), tostring(bAlive)))
end
P("  ── 已建城 "..nActive.." / 休眠 "..nDorm)
"""
    + EPILOGUE
)


# ---- 93. 结束回合（让城邦建城）--------------------------------------------
PROBES["endturn"] = (
    PRELUDE
    + r"""
P("== 结束回合 ==")
local bOk, err = pcall(function() Network.SendEndTurn() end)
P("  SendEndTurn ok="..tostring(bOk).."  err="..tostring(err))
local t = 0
pcall(function() t = Game.GetTurn() end)
P("  当前回合 = "..tostring(t))
"""
    + EPILOGUE
)


# ---- 94. 反复推进若干回合，直到城邦建城或超时 -------------------------------
PROBES["pump"] = (
    PRELUDE
    + r"""
P("== 推进回合（最多 6 次）==")
for i = 1, 6 do
  local t = 0
  pcall(function() t = Game.GetTurn() end)
  -- 统计已建城的城邦
  local nCity = 0
  local tIDs = {}
  pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
  for _, id in ipairs(tIDs) do
    local c = 0
    pcall(function() c = Players[id]:GetCities():GetCount() end)
    if c > 0 then nCity = nCity + 1 end
  end
  P("  [轮 "..i.."] turn="..tostring(t).."  已建城城邦 = "..nCity)
  if nCity >= 7 then P("  🎉 额外城邦已建城，停止推进") break end
  pcall(function() Network.SendEndTurn() end)
  -- 等待（tuner 侧无法 sleep，靠多次短调用错开）
  local x = 0
  for j = 1, 300000 do x = x + 1 end
end
P("== 推进结束 ==")
"""
    + EPILOGUE
)


# ---- 95. 对照：建一个【原生休眠城邦】（已知可用路径）------------------------
PROBES["foundnormal"] = (
    PRELUDE
    + r"""
local okBody, errBody = pcall(function()

local CSF = ExposedMembers and ExposedMembers.CSF
P("== 对照测试：建一个【原生】休眠城邦（槽 < 50）==")
if CSF == nil then P("❌ ExposedMembers.CSF 不可用") return end

local iMe = Game.GetLocalPlayer()

-- 找一个槽 < 50 的休眠城邦
local iTarget, sCiv = nil, nil
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
for _, id in ipairs(tIDs) do
  if id < 50 then
    local c, onMap = 0, false
    pcall(function() c = Players[id]:GetCities():GetCount() end)
    pcall(function()
      for _, u in Players[id]:GetUnits():Members() do
        local x, y = u:GetX(), u:GetY()
        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then onMap = true break end
      end
    end)
    if c == 0 and not onMap and iTarget == nil then
      iTarget = id
      pcall(function() sCiv = PlayerConfigurations[id]:GetCivilizationTypeName() end)
    end
  end
end
P("  目标 = id "..tostring(iTarget).."  "..tostring(sCiv))
if iTarget == nil then P("❌ 没有原生休眠城邦") return end

-- 找合法位置
local iX, iY = nil, nil
pcall(function()
  local ux, uy = nil, nil
  for _, u in Players[iMe]:GetUnits():Members() do
    local x, y = u:GetX(), u:GetY()
    if x ~= nil and y ~= nil and x >= 0 and y >= 0 then ux, uy = x, y break end
  end
  P("  参考单位在 ("..tostring(ux)..","..tostring(uy)..")")
  if ux == nil then return end
  for r = 1, 10 do
    for dx = -r, r do
      for dy = -r, r do
        if iX == nil then
          local x, y = ux + dx, uy + dy
          local bOk = false
          pcall(function()
            if Map.GetPlot(x, y) ~= nil then bOk = CSF.IsValidLocation(x, y, iMe) end
          end)
          if bOk then iX, iY = x, y end
        end
      end
    end
    if iX ~= nil then break end
  end
end)
P("  选定位置 = ("..tostring(iX)..","..tostring(iY)..")")
if iX == nil then P("❌ 没找到合法位置") return end

P("== 调用 FoundCityStateByCiv ==")
local ok, reason, pid, bFull = CSF.FoundCityStateByCiv(sCiv, iX, iY, nil, iMe)
P("  ok="..tostring(ok).."  reason="..tostring(reason)..
  "  playerID="..tostring(pid).."  full="..tostring(bFull))

end)
if not okBody then P("❌❌ 探针体出错："..tostring(errBody)) end
"""
    + EPILOGUE
)


# ---- 96. ⭐ 统计函数 + 保留比例实测（T-146 / T-147）--------------------------
PROBES["statsprobe"] = (
    PRELUDE
    + r"""
P("== 1. ⭐ CSF_GetGameCityStateStats（面板计数修正 T-147 用）==")
local fStats = ExposedMembers and ExposedMembers.CSF and ExposedMembers.CSF.GetGameCityStateStats
if fStats == nil then
  P("  ❌ ExposedMembers.CSF.GetGameCityStateStats 不可用")
else
  local okS, kS = pcall(fStats)
  if okS and type(kS) == "table" then
    P("  total   = "..tostring(kS.total).."   （本局城邦玩家总数）")
    P("  dormant = "..tostring(kS.dormant).."   （休眠中 = 可建）")
    P("  active  = "..tostring(kS.active).."   （已建城、在地图上正常运作）")
    P("  pending = "..tostring(kS.pending).."   （0 城但已有单位 = 已派出、等自己建城）")
    P("  pool    = "..tostring(kS.pool).."   （城邦池大小，参考值 —— 不要当成本局城邦数）")
    if kS.total ~= nil and kS.dormant ~= nil and kS.active ~= nil then
      local iSum = (kS.dormant or 0) + (kS.active or 0) + (kS.pending or 0)
      if kS.total == iSum then
        P("  ✅ total = dormant + active + pending 自洽")
      else
        P("  ⚠️ total ≠ dormant + active + pending（"..tostring(kS.total)..
          " vs "..tostring(iSum).."）")
      end
    end
  else
    P("  ❌ 调用失败："..tostring(kS))
  end
end

P("")
P("== 2. 保留比例实测（T-146）==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local iTotal, iDormant, iActive = 0, 0, 0
for _, id in ipairs(tIDs) do
  iTotal = iTotal + 1
  local c = 0
  pcall(function() c = Players[id]:GetCities():GetCount() end)
  if c > 0 then
    iActive = iActive + 1
  else
    local onMap = false
    pcall(function()
      for _, u in Players[id]:GetUnits():Members() do
        local x, y = u:GetX(), u:GetY()
        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then onMap = true break end
      end
    end)
    if not onMap then iDormant = iDormant + 1 end
  end
end
P("  本局城邦总数 T   = "..iTotal)
P("  地图上（已建城） = "..iActive)
P("  休眠（可建）     = "..iDormant)
if iTotal > 0 then
  P(string.format("  实际保留比例     = %.0f%%（目标 50%%）", iActive * 100 / iTotal))
  if iDormant > 0 then
    P("  ✅ 可建数量 > 0 —— 小地图静默失效问题已修复")
  else
    P("  ⚠️ 可建数量 = 0（可能是本局城邦数太少，或开关被设成了绝对值）")
  end
end
"""
    + EPILOGUE
)


# ---- 97. ⭐ MapSizes 是否真的被模组改到了（T-148）----------------------------
#   ⚠️ 查 DebugConfiguration.sqlite 是【错的方法】—— 那是基础库快照。
#      正确做法：运行时用 DB.ConfigurationQuery 读【活库】。
PROBES["mapsizesprobe"] = (
    PRELUDE
    + r"""
P("== 运行时读配置库 MapSizes（活库，不是磁盘快照）==")
P("  ⚠️ MapSizes 有 Domain 列 —— 必须带上，否则不同域的行会混在一起")
local okQ, tRows = pcall(function()
  return DB.ConfigurationQuery(
    "SELECT Domain, MapSizeType, MinCityStates, MaxCityStates, DefaultCityStates " ..
    "FROM MapSizes ORDER BY Domain, SortIndex")
end)
if not okQ or type(tRows) ~= "table" then
  P("  ❌ DB.ConfigurationQuery 失败："..tostring(tRows))
  P("  （本上下文可能读不到配置库 —— 需要在 InGame/前端上下文跑）")
else
  P("  共 "..#tRows.." 行")
  P(string.format("  %-26s %-20s %5s %5s %8s", "Domain", "MapSize", "Min", "Max", "Default"))
  for _, r in ipairs(tRows) do
    P(string.format("  %-26s %-20s %5s %5s %8s",
      tostring(r.Domain), tostring(r.MapSizeType), tostring(r.MinCityStates),
      tostring(r.MaxCityStates), tostring(r.DefaultCityStates)))
  end
  P("")
  P("  官方原值对照（StandardMapSizes 域）：")
  P("    DUEL 0/6/3  TINY 0/10/6  SMALL 0/14/9  STANDARD 0/18/12  LARGE 0/22/15  HUGE 0/24/18")
  P("  → 若某域的 Max/Default 比上面大 4，说明模组的 UPDATE 生效了 ✅")
end

P("")
P("== MapConfiguration 接口（另一条路）==")
local f1 = MapConfiguration and MapConfiguration.GetMaxMinorPlayers
if f1 == nil then
  P("  MapConfiguration 或 GetMaxMinorPlayers 不可用（本上下文没有）")
else
  local okM, mx = pcall(f1)
  P("  MapConfiguration.GetMaxMinorPlayers() = "..tostring(mx))
  local f2 = MapConfiguration.GetMinMinorPlayers
  if f2 ~= nil then
    local okN, mn = pcall(f2)
    P("  MapConfiguration.GetMinMinorPlayers() = "..tostring(mn))
  end
end
"""
    + EPILOGUE
)


# ---- 98. ⭐ 高城邦数开局（T-153：测"滑条拉满后地图容量够不够"）-------------
#   背景：普通 startgame 探针走 OnPlayCiv6()，用的是参数默认值（本机实测固定 9 个城邦），
#         改 MapSizes.DefaultCityStates 也影响不到它 —— 所以测不出容量上限。
#   做法：复刻 MainMenu.lua 的开局流程，但在 HostGame 之前把 CityStateCount 直接设高。
PROBES["startgame_highcount"] = (
    PRELUDE
    + r"""
P("== 高城邦数开局（复刻 MainMenu 流程 + 覆盖 CityStateCount）==")

-- 目标城邦数：从参数里取（默认 22 = 标准图抬高后的上限）
local iWant = 22
P("  目标城邦数 = "..iWant)

P("== 1. 建参数 ==")
local okB = pcall(BuildHeadlessGameSetup)
P("  BuildHeadlessGameSetup ok="..tostring(okB))
if not okB then P("  ❌ 中止") return end

P("== 2. 列出所有参数（找 CityStateCount）==")
local kParam = nil
pcall(function()
  if g_GameParameters ~= nil and g_GameParameters.Parameters ~= nil then
    for k, v in pairs(g_GameParameters.Parameters) do
      if k == "CityStateCount" then kParam = v end
      if k == "MapSize" or k == "MapScript" or k == "Ruleset" then
        P("   "..tostring(k).." = "..tostring(v.Value))
      end
    end
  end
end)
P("  CityStateCount 参数对象 = "..tostring(kParam ~= nil))
if kParam == nil then P("  ❌ 拿不到参数对象，中止") return end
P("   当前值 = "..tostring(kParam.Value))
pcall(function()
  if kParam.Values ~= nil then
    P("   允许范围 = "..tostring(kParam.Values.MinimumValue).." .. "..tostring(kParam.Values.MaximumValue))
  end
end)

P("== 3. 把 CityStateCount 设成目标值 ==")
local bSet = pcall(function()
  g_GameParameters:SetParameterValue(kParam, iWant)
end)
P("  SetParameterValue ok="..tostring(bSet).."  现在值 = "..tostring(kParam.Value))

P("== 4. 刷新 + 释放 + 开局 ==")
pcall(function() RebuildPlayerParameters(true) end)
pcall(function() GameSetup_RefreshParameters() end)
pcall(function() ReleasePlayerParameters() end)
pcall(function() HideGameSetup() end)
local okH = pcall(function() Network.HostGame(ServerType.SERVER_TYPE_NONE) end)
P("  Network.HostGame ok="..tostring(okH))
P("  👉 若地图能生成，说明高城邦数不超容量；若进程消失/卡住，说明超了")
"""
    + EPILOGUE
)


# ---- 99. ⭐ 量本局地图的真实网格尺寸 + 城邦容量相关参数（T-154）------------
PROBES["mapsize_probe"] = (
    PRELUDE
    + r"""
P("== 1. 本局地图真实尺寸 ==")
local w, h = nil, nil
pcall(function() w, h = Map.GetGridSize() end)
P("  Map.GetGridSize() = "..tostring(w).." x "..tostring(h))
if w ~= nil and h ~= nil then P("  总格数 = "..tostring(w * h)) end
local ms = nil
pcall(function() ms = Map.GetMapSize() end)
P("  Map.GetMapSize() = "..tostring(ms))
pcall(function()
  if ms ~= nil and GameInfo.Maps[ms] ~= nil then
    P("  GameInfo.Maps[ms].MapSizeType = "..tostring(GameInfo.Maps[ms].MapSizeType))
  end
end)

P("")
P("== 2. 城邦间距相关的 GlobalParameters ==")
for _, nm in ipairs({
  "START_DISTANCE_MINOR_CIVILIZATION_START",
  "START_DISTANCE_MINOR_MAJOR_CIVILIZATION",
  "START_DISTANCE_MAJOR_CIVILIZATION_START",
}) do
  local v = nil
  pcall(function() v = GameInfo.GlobalParameters[nm].Value end)
  if v == nil then pcall(function() v = GlobalParameters[nm] end) end
  P(string.format("  %-46s = %s", nm, tostring(v)))
end

P("")
P("== 3. 本局玩家统计 ==")
local iMajors = 0
pcall(function() iMajors = #PlayerManager.GetAliveMajorIDs() end)
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  存活主文明 = "..iMajors)
P("  存活城邦   = "..#tIDs)

P("")
P("== 4. CCB Maps 的运行时属性 ==")
for _, k in ipairs({"BBM_ACTUALMINDIST", "BBM_MAJOR_DISTANCE", "BBM_RESPAWN"}) do
  local v = nil
  pcall(function() v = Game:GetProperty(k) end)
  P(string.format("  %-24s = %s", k, tostring(v)))
end
"""
    + EPILOGUE
)


# ---- 100. ⭐ UI 可改写性 + 颜色按文明查询（T-155）------------------------
PROBES["uicolor_probe"] = (
    PRELUDE
    + r"""
P("== 1. UI 是什么类型（决定能不能 monkey-patch）==")
P("  type(UI) = "..type(UI))
local mt = nil
pcall(function() mt = getmetatable(UI) end)
P("  getmetatable(UI) = "..tostring(mt))
local bNewIdx = false
pcall(function()
  UI.__csf_test = 12345
  bNewIdx = (UI.__csf_test == 12345)
  UI.__csf_test = nil
end)
P("  → 能给 UI 加字段吗 = "..tostring(bNewIdx).."  （true = 是 Lua 表，可 monkey-patch）")

P("")
P("== 2. UI 上所有含 Color 的方法 ==")
local tNames = {}
pcall(function()
  for k, v in pairs(UI) do
    if type(k) == "string" and string.find(k, "Color") then
      tNames[#tNames+1] = k.." ("..type(v)..")"
    end
  end
end)
table.sort(tNames)
for _, s in ipairs(tNames) do P("  "..s) end
P("  共 "..tostring(#tNames).." 个")

P("")
P("== 3. ⭐ 颜色能不能按【文明】查出来 ==")
local tCivs = {"CIVILIZATION_ANTIOCH", "CIVILIZATION_KUMASI", "CIVILIZATION_BRUSSELS",
               "CIVILIZATION_HONG_KONG", "CIVILIZATION_VALLETTA", "CIVILIZATION_GENEVA",
               "CIVILIZATION_AMSTERDAM", "CIVILIZATION_ZANZIBAR"}
for _, civ in ipairs(tCivs) do
  local line = "  "..civ
  for i = 0, 1 do
    local a, b = nil, nil
    pcall(function() a, b = UI.GetPlayerColorValues(civ, i) end)
    line = line.."  ["..i.."]="..tostring(a).."/"..tostring(b)
  end
  P(line)
end

P("")
P("== 4. 本局所有城邦：slot 颜色 vs 文明颜色 对照 ==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
P("  存活城邦 "..#tIDs.." 个")
for i, pid in ipairs(tIDs) do
  if i > 6 then P("  ...（只列前 6 个）"); break end
  local sCiv = "?"
  pcall(function() sCiv = PlayerConfigurations[pid]:GetCivilizationTypeName() end)
  local a1, b1 = nil, nil
  pcall(function() a1, b1 = UI.GetPlayerColors(pid) end)
  local a2, b2 = nil, nil
  pcall(function() a2, b2 = UI.GetPlayerColorValues(sCiv, 0) end)
  P(string.format("  pid=%-3s %-32s slot=%s/%s  civ=%s/%s",
      tostring(pid), sCiv, tostring(a1), tostring(b1), tostring(a2), tostring(b2)))
end

P("")
P("== 5. UI.GetPlayerColors 是不是纯 Lua 函数（能否被包装）==")
local info = nil
pcall(function() info = debug.getinfo(UI.GetPlayerColors) end)
P("  debug.getinfo = "..tostring(info))
if info ~= nil then
  P("  source = "..tostring(info.source).."  what = "..tostring(info.what))
end
"""
    + EPILOGUE
)


# ---- 101. ⭐ 槽位全景（找可激活的预分配城邦槽，T-155）---------------------
PROBES["slots_probe"] = (
    PRELUDE
    + r"""
P("== 全部 64 槽位全景 ==")
P("  slot  status  civ                               leader                            alive  cities  units")
P("  ----  ------  --------------------------------  --------------------------------  -----  ------  -----")
local iUsed, iFree, iStatus5 = 0, 0, 0
local tPreAssigned = {}
for i = 0, 63 do
  local sCiv, sLeader, iStatus = "?", "?", -1
  pcall(function() sCiv = PlayerConfigurations[i]:GetCivilizationTypeName() or "" end)
  pcall(function() sLeader = PlayerConfigurations[i]:GetLeaderTypeName() or "" end)
  pcall(function() iStatus = PlayerConfigurations[i]:GetSlotStatus() end)

  local bAlive, iCities, iUnits = false, 0, 0
  pcall(function() bAlive = Players[i]:IsAlive() end)
  pcall(function() iCities = Players[i]:GetCities():GetCount() end)
  pcall(function()
    local u = Players[i]:GetUnits()
    if u ~= nil then iUnits = u:GetNumMilitaryUnits() + u:GetNumCivilianUnits() end
  end)

  local sMark = ""
  if sCiv ~= nil and sCiv ~= "" then
    iUsed = iUsed + 1
    if iStatus == 5 then iStatus5 = iStatus5 + 1; tPreAssigned[#tPreAssigned+1] = i; sMark = " ★预分配" end
  else
    iFree = iFree + 1
    sMark = " （空）"
  end

  P(string.format("  %4d  %6s  %-32s  %-32s  %-5s  %6d  %5d%s",
      i, tostring(iStatus), tostring(sCiv), tostring(sLeader),
      tostring(bAlive), iCities, iUnits, sMark))
end
P("")
P("  已占用 "..iUsed.." 槽 / 空 "..iFree.." 槽 / status=5 预分配 "..iStatus5.." 槽")
if #tPreAssigned > 0 then
  local s = ""
  for _, v in ipairs(tPreAssigned) do s = s..tostring(v).." " end
  P("  ★ 预分配槽列表: "..s)
end

P("")
P("== 存活城邦的槽位 ==")
local tIDs = {}
pcall(function() tIDs = PlayerManager.GetAliveMinorIDs() end)
local s2 = ""
for _, v in ipairs(tIDs) do s2 = s2..tostring(v).." " end
P("  "..s2)

P("")
P("== 城邦池（配置库）有多少 ==")
local tAll = {}
pcall(function() tAll = DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates") end)
P("  CityStates 表总行数 = "..#tAll)
"""
    + EPILOGUE
)


# ---- 102. ⭐ WorldBuilder.PlayerManager 全部方法（找"激活预分配槽"的 API）----
PROBES["pm_methods"] = (
    PRELUDE
    + r"""
P("== 1. WorldBuilder 是否存在 ==")
P("  WorldBuilder = "..tostring(WorldBuilder))
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
P("  WorldBuilder.PlayerManager() = "..tostring(pm))
if pm == nil then
  P("  ❌ 拿不到 PlayerManager，中止")
  return
end

P("")
P("== 2. PlayerManager 上所有方法（含关键字过滤）==")
local tAll = {}
pcall(function()
  for k, v in pairs(pm) do
    if type(k) == "string" then tAll[#tAll+1] = k.." ["..type(v).."]" end
  end
end)
table.sort(tAll)
P("  共 "..tostring(#tAll).." 个成员：")
for _, s in ipairs(tAll) do P("    "..s) end

P("")
P("== 3. ⭐ 与槽位/状态/激活相关的方法（重点）==")
local tKey = {"Slot", "Status", "Alive", "Activate", "Add", "Remove", "Kill", "Revive",
              "Enable", "Disable", "Init", "Set", "Minor", "Major", "Start", "Player"}
for _, kw in ipairs(tKey) do
  local tHit = {}
  for _, s in ipairs(tAll) do
    if string.find(s, kw, 1, true) then tHit[#tHit+1] = s end
  end
  if #tHit > 0 then
    P("  --- 含 '"..kw.."' ---")
    for _, s in ipairs(tHit) do P("      "..s) end
  end
end

P("")
P("== 4. PlayerConfigurations 上的方法（看有没有改槽位状态的）==")
local tCfg = {}
pcall(function()
  for k, v in pairs(PlayerConfigurations[15]) do
    if type(k) == "string" then tCfg[#tCfg+1] = k.." ["..type(v).."]" end
  end
end)
table.sort(tCfg)
P("  共 "..tostring(#tCfg).." 个：")
for _, s in ipairs(tCfg) do P("    "..s) end

P("")
P("== 5. 槽 15（预分配城邦）现在能不能被查询 ==")
local sCiv = "?"
pcall(function() sCiv = PlayerConfigurations[15]:GetCivilizationTypeName() end)
P("  PlayerConfigurations[15]:GetCivilizationTypeName() = "..tostring(sCiv))
local bAlive = nil
pcall(function() bAlive = Players[15]:IsAlive() end)
P("  Players[15]:IsAlive() = "..tostring(bAlive))
local sLeader = "?"
pcall(function() sLeader = Players[15]:GetLeaderTypeName() end)
P("  Players[15]:GetLeaderTypeName() = "..tostring(sLeader))
local iTeam = nil
pcall(function() iTeam = Players[15]:GetTeam() end)
P("  Players[15]:GetTeam() = "..tostring(iTeam))
"""
    + EPILOGUE
)


# ---- 103. ⭐ 试探 PlayerManager 有没有"激活预分配槽"的接口（T-156）--------
PROBES["pm_activate_probe"] = (
    PRELUDE
    + r"""
P("== 1. 拿 PlayerManager ==")
local pm = nil
pcall(function() pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager() end)
P("  pm = "..tostring(pm))
if pm == nil then P("  ❌ 不可用"); return end

P("")
P("== 2. 挨个试方法名（只看"存不存在"，不真的改状态）==")
local tNames = {
  -- 激活 / 槽位状态
  "ActivatePlayer", "SetPlayerSlotStatus", "SetSlotStatus", "SetPlayerStatus",
  "EnablePlayer", "RevivePlayer", "RespawnPlayer", "AddExistingPlayer",
  -- 增删
  "AddPlayer", "RemovePlayer", "DeletePlayer", "KillPlayer",
  -- 领袖 / 文明
  "SetPlayerLeader", "SetPlayerCivilization", "SetPlayerTeam", "SetPlayerHandicap",
  -- 位置
  "SetStartingPlot", "SetRandomMinorStartingPosition", "SetRandomMajorStartingPosition",
  -- 查询
  "GetPlayer", "GetNumPlayers", "IsPlayerAlive", "IsPlayerInitialized",
  "GetPlayerSlotStatus", "GetFreeSlot", "GetNumFreeSlots",
}
for _, n in ipairs(tNames) do
  local v = nil
  pcall(function() v = pm[n] end)
  P(string.format("  %-36s %s", n, tostring(v)))
end

P("")
P("== 3. 直接试几个可能的"激活"调用（包 pcall，失败无副作用）==")
local iTest = 15   -- 一个预分配的城邦槽
local sCiv = "?"
pcall(function() sCiv = PlayerConfigurations[iTest]:GetCivilizationTypeName() end)
P("  测试槽 "..iTest.." = "..tostring(sCiv))
local tTry = {"SetPlayerSlotStatus", "ActivatePlayer", "EnablePlayer", "RevivePlayer"}
for _, n in ipairs(tTry) do
  local b = pcall(function()
    if pm[n] ~= nil then pm[n](pm, iTest, 1) end
  end)
  local b2 = pcall(function()
    if pm[n] ~= nil then pm[n](pm, iTest) end
  end)
  P(string.format("  %-24s 三参=%s  两参=%s", n, tostring(b), tostring(b2)))
end

P("")
P("== 4. 试完之后槽 15 的状态 ==")
local iSt = -1
pcall(function() iSt = PlayerConfigurations[iTest]:GetSlotStatus() end)
local bAlive = nil
pcall(function() bAlive = Players[iTest]:IsAlive() end)
P("  槽 "..iTest.." status="..tostring(iSt).."  alive="..tostring(bAlive))
"""
    + EPILOGUE
)


# --------------------------------------------------------------------------
async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", help="探针名；--list 查看全部")
    ap.add_argument("--probes", help="⭐ 批量：逗号分隔的多个探针名，在【同一条连接】上依次跑")
    ap.add_argument("--state", help="目标 Lua 状态名（模糊匹配），默认 0")
    ap.add_argument("--all-states", action="store_true", help="在所有状态里跑同一探针")
    ap.add_argument("--eval", dest="code", help="直接执行一段 Lua")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--port", type=int, default=None,
                    help="FireTuner 端口；**默认 None = 自动发现**（4318 被占用时引擎会顺延到 4319）")
    ap.add_argument("--quiet", action="store_true", help="不打印状态列表（省输出）")
    ap.add_argument("--wait-state", help="⭐ 在同一条连接上轮询等待某状态出现")
    ap.add_argument("--wait-timeout", type=float, default=300.0, help="等待超时秒数")
    args = ap.parse_args()

    if args.list:
        print("可用探针：")
        for k in PROBES:
            print("  -", k)
        return

    try:
        reader, writer = await connect(args.port)
    except Exception as e:
        print(f"[FAIL] 连不上 {HOST}:{PORT} -> {e}")
        print("       游戏未运行 / EnableTuner 未开 / 当前是多人局（多人局 4318 被引擎硬禁用）")
        sys.exit(2)

    app, states = await handshake(reader, writer)
    name_of = dict(states)
    if not args.quiet:
        print(f"游戏标识: {app}")
        print(f"Lua 状态 ({len(states)}):")
        for idx, name in states:
            print(f"  {idx:>3}: {name}")
        print("-" * 70)
    else:
        print(f"状态数 {len(states)}")

    # ---- ⭐ 连接复用轮询：全程只用这一条连接，不重连 ----
    if args.wait_state:
        import time as _t
        deadline = _t.time() + args.wait_timeout
        found = None
        while _t.time() < deadline:
            idx = pick_state(states, args.wait_state)
            nm = name_of.get(idx, "")
            if args.wait_state.lower() in nm.lower():
                found = idx
                break
            await asyncio.sleep(8)
            # 同一条连接上重新握手（发 LSQ:），不新建连接
            try:
                await send_message(writer, TAG_HANDSHAKE, "LSQ:")
                for _ in range(8):
                    m = await recv_message(reader, 5.0)
                    if m is None:
                        break
                    cand = parse_states(m[1])
                    if any(n == "Main State" for _, n in cand):
                        states = cand
                        name_of = dict(states)
                        break
                await drain(reader, 0.5)
            except Exception as ex:
                print(f"  [wait] LSQ 异常: {ex}")
        if found is None:
            print(f"[FAIL] 等待 '{args.wait_state}' 超时（{args.wait_timeout}s）")
            await close_conn(writer)
            sys.exit(3)
        print(f"[OK] 状态 '{args.wait_state}' 已就绪 -> index {found}")
        states = [(found, args.wait_state)]
        # 只跑探针，不再重复报状态

    # ---- ⭐ 批量探针：同一条连接依次跑完 ----
    if args.probes:
        names = [x.strip() for x in args.probes.split(",") if x.strip()]
        idx = pick_state(states, args.state)
        for nm in names:
            code = PROBES.get(nm)
            if code is None:
                print(f"[FAIL] 未知探针 '{nm}'")
                continue
            print(f"\n########## 探针 {nm} @ state {idx} ##########")
            resp, extra = await run_lua(reader, writer, idx, code, timeout=60.0)
            if resp:
                print(f"[响应] {resp}")
            for e in extra:
                print(e)
        await close_conn(writer)
        return

    if args.code:
        idx = pick_state(states, args.state)
        resp, extra = await run_lua(reader, writer, idx, args.code)
        print(f"[state {idx}] 响应: {resp}")
        for e in extra:
            print(e)
    elif args.probe:
        code = PROBES.get(args.probe)
        if code is None:
            print(f"[FAIL] 未知探针 '{args.probe}'；用 --list 查看")
            sys.exit(2)
        targets = (
            [i for i, _ in states] if args.all_states else [pick_state(states, args.state)]
        )
        for idx in targets:
            print(f"\n########## 状态 {idx}: {name_of.get(idx, '?')} ##########")
            resp, extra = await run_lua(reader, writer, idx, code, timeout=12.0)
            if resp:
                print(f"[响应] {resp}")
            for e in extra:
                print(e)
    elif not args.wait_state:
        print("用 --probe <name> / --probes a,b,c / --eval <lua> / --list")

    await close_conn(writer)

    await close_conn(writer)


if __name__ == "__main__":
    asyncio.run(main())
