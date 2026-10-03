-- ★★ 开局 v3 —— 用【默认城邦数】排除"数量超容量"这个嫌疑
print("=== 开局 v3：默认城邦数 ===")

-- ── 1. 参数：只用默认值，不抬城邦数 ────────────────────────────────────
print("")
print("=== 1. 参数（不抬城邦数）===")
pcall(function() GameConfiguration.SetValue("RULESET", "RULESET_EXPANSION_2") end);
local vCS = nil; pcall(function() vCS = GameConfiguration.GetValue("CITY_STATE_COUNT") end);
local vMS = nil; pcall(function() vMS = MapConfiguration.GetValue("MAP_SIZE") end);
local vSC = nil; pcall(function() vSC = MapConfiguration.GetValue("MAP_SCRIPT") end);
print("  CITY_STATE_COUNT = " .. tostring(vCS) .. "   （默认值，不动）");
print("  MAP_SIZE         = " .. tostring(vMS));
print("  MAP_SCRIPT       = " .. tostring(vSC));

-- ── 2. 玩家槽位 ────────────────────────────────────────────────────────
print("")
print("=== 2. 玩家槽位 ===")
local pc0 = PlayerConfigurations[0];
if pc0 == nil then print("  ❌ slot0 nil"); return end
local sCiv, sLeader, sLeaderName = nil, nil, nil;
pcall(function()
  for row in GameInfo.Civilizations() do
    if row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_FULL_CIV" then
      sCiv = row.CivilizationType; break; end
  end
end);
pcall(function()
  for row in GameInfo.Leaders() do
    local nm = nil; pcall(function() nm = Locale.Lookup(row.Name) end);
    if nm ~= nil and tostring(nm) ~= "" and row.LeaderType ~= "LEADER_DEFAULT" then
      sLeader = row.LeaderType; sLeaderName = tostring(nm); break; end
  end
end);
if sCiv ~= nil then pcall(function() pc0:SetCivilizationTypeName(sCiv) end) end;
if sLeader ~= nil then pcall(function() pc0:SetLeaderTypeName(sLeader) end) end;
if sLeaderName ~= nil then pcall(function() pc0:SetLeaderName(sLeaderName) end) end;
pcall(function() pc0:SetSlotStatus(3) end);
pcall(function() Network.BroadcastPlayerInfo(0) end);
local c1, l1, s1 = nil, nil, nil;
pcall(function() c1 = pc0:GetCivilizationTypeName() end);
pcall(function() l1 = pc0:GetLeaderTypeName() end);
pcall(function() s1 = pc0:GetSlotStatus() end);
print(string.format("  slot0: civ=%s leader=%s status=%s", tostring(c1), tostring(l1), tostring(s1)));

-- ── 3. 补齐地图参数（AgentHost AH_PrepareRoom 的做法）──────────────────
print("")
print("=== 3. 补齐地图参数（照 AH_PrepareRoom）===")
for _, kv in ipairs({ { "resources", 2 }, { "start", 2 }, { "temperature", 2 },
                      { "rainfall", 2 }, { "sea_level", 2 }, { "world_age", 2 } }) do
  local ok, cur = pcall(function() return MapConfiguration.GetValue(kv[1]) end);
  if not ok or cur == nil then
    pcall(function() MapConfiguration.SetValue(kv[1], kv[2]) end);
    print("   补齐 " .. kv[1] .. " = " .. kv[2]);
  end
end

-- ── 4. 自动开始 ────────────────────────────────────────────────────────
print("")
print("=== 4. Automation ===")
pcall(function() Automation.SetAutoStartEnabled(true) end);
local okS = false; pcall(function() okS = Automation.IsAutoStartEnabled() end);
print("  autostart=" .. tostring(okS));

-- ── 5. 游戏入口方式 + 广播 ─────────────────────────────────────────────
print("")
print("=== 5. SetGameEntryMethod + BroadcastGameConfig ===")
pcall(function() Events.SetGameEntryMethod("Create a Game") end);
pcall(function() if Network.BroadcastGameConfig ~= nil then Network.BroadcastGameConfig() end end);
local sEM = nil; pcall(function() sEM = Events.GetGameEntryMethod() end);
print("  entryMethod=" .. tostring(sEM));

-- ── 6. HostGame ────────────────────────────────────────────────────────
print("")
print("=== 6. HostGame ===")
local bH = pcall(function() Network.HostGame(ServerType.SERVER_TYPE_NONE) end);
print("  HostGame ok=" .. tostring(bH));
print("=== 完成 ===")
