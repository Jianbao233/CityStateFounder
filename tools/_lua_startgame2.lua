-- ★★ 完整开局 v2 —— 补上 AgentHost v40 的关键步骤 Events.SetGameEntryMethod
-- 依据：AgentHost.lua:447-452（实测修正：不调它 → 引擎不按新游戏初始化 → early exit）
print("=== 完整开局 v2 ===")

print("")
print("=== 1. 城邦数 + 规则集 ===")
pcall(function() GameConfiguration.SetValue("CITY_STATE_COUNT", 22) end);
pcall(function() GameConfiguration.SetValue("RULESET", "RULESET_EXPANSION_2") end);
local v = nil; pcall(function() v = GameConfiguration.GetValue("CITY_STATE_COUNT") end);
print("  CITY_STATE_COUNT = " .. tostring(v));

print("")
print("=== 2. 配玩家槽位 ===")
-- ★ AgentHost v28：主机也必须分配【有效领袖】—— 跳过占位 LEADER_DEFAULT。
--   空领袖（LEADER_TYPE_NAME 空 + POOL 0）会导致 GameCore 创建对局【提前退出】。
local pc0 = PlayerConfigurations[0];
if pc0 == nil then print("  ❌ slot0 为 nil"); return end

local sCiv, sLeader, sLeaderName = nil, nil, nil;
pcall(function()
  for row in GameInfo.Civilizations() do
    if row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_FULL_CIV" then
      sCiv = row.CivilizationType; break;
    end
  end
end);
-- ★ 挑一个"名字非空"的领袖（跳过 LEADER_DEFAULT 这类占位）
pcall(function()
  for row in GameInfo.Leaders() do
    local nm = nil;
    pcall(function() nm = Locale.Lookup(row.Name) end);
    if nm ~= nil and tostring(nm) ~= "" and row.LeaderType ~= "LEADER_DEFAULT" then
      sLeader = row.LeaderType; sLeaderName = tostring(nm); break;
    end
  end
end);
print("  civ=" .. tostring(sCiv) .. "  leader=" .. tostring(sLeader) ..
      "  name=" .. tostring(sLeaderName));

if sCiv ~= nil then pcall(function() pc0:SetCivilizationTypeName(sCiv) end) end;
if sLeader ~= nil then pcall(function() pc0:SetLeaderTypeName(sLeader) end) end;
if sLeaderName ~= nil then pcall(function() pc0:SetLeaderName(sLeaderName) end) end;
pcall(function() pc0:SetSlotStatus(3) end);          -- 3 = Human
pcall(function() Network.BroadcastPlayerInfo(0) end);

local c1, l1, n1, s1 = nil, nil, nil, nil;
pcall(function() c1 = pc0:GetCivilizationTypeName() end);
pcall(function() l1 = pc0:GetLeaderTypeName() end);
pcall(function() n1 = pc0:GetLeaderName() end);
pcall(function() s1 = pc0:GetSlotStatus() end);
print(string.format("  复查: civ=%s leader=%s name=%s status=%s",
      tostring(c1), tostring(l1), tostring(n1), tostring(s1)));

print("")
print("=== 3. 单机不预填 AI 槽（AgentHost v38：预填 COMPUTER 会导致单机建局失败）===")
print("  AI 槽保持 OPEN，引擎开局自动分配");

print("")
print("=== 4. Automation.SetAutoStartEnabled(true) ===")
pcall(function() Automation.SetAutoStartEnabled(true) end);
local okS = false; pcall(function() okS = Automation.IsAutoStartEnabled() end);
print("  autostart=" .. tostring(okS));

print("")
print("=== 5. ★★ Events.SetGameEntryMethod(\"Create a Game\") ===")
local bEM = pcall(function() Events.SetGameEntryMethod("Create a Game") end);
local sEM = nil; pcall(function() sEM = Events.GetGameEntryMethod() end);
print("  调用 ok=" .. tostring(bEM) .. "  现在=" .. tostring(sEM));

print("")
print("=== 6. HostGame(ServerType.SERVER_TYPE_NONE) ===")
local bH = pcall(function() Network.HostGame(ServerType.SERVER_TYPE_NONE) end);
print("  HostGame ok=" .. tostring(bH));
print("=== 完成 ===")
