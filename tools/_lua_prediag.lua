-- ★ 开局前全量诊断：所有槽位 + 全部参数（找 early exit 的缺失项）
print("=== 开局前全量诊断 ===")

print("")
print("=== 1. 所有玩家槽位（0~63）===")
local nTaken, nOpen, nComp, nClosed = 0, 0, 0, 0;
for i = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[i] end);
  if pc ~= nil then
    local civ, ldr, st = nil, nil, nil;
    pcall(function() civ = pc:GetCivilizationTypeName() end);
    pcall(function() ldr = pc:GetLeaderTypeName() end);
    pcall(function() st = pc:GetSlotStatus() end);
    if st ~= nil then
      if st == 0 then nOpen = nOpen + 1
      elseif st == 1 then nComp = nComp + 1
      elseif st == 2 then nClosed = nClosed + 1
      else nTaken = nTaken + 1 end
    end
    if i < 8 or (civ ~= nil and civ ~= "") then
      print(string.format("  slot %2d  ss=%-3s civ=%-26s leader=%s",
            i, tostring(st), tostring(civ), tostring(ldr)));
    end
  end
end
print(string.format("  统计: Open=%d AI=%d Closed=%d 其他=%d", nOpen, nComp, nClosed, nTaken));

print("")
print("=== 2. SlotStatus 枚举（Lua 层）===")
for _, k in ipairs({ "SS_OPEN", "SS_CLOSED", "SS_COMPUTER", "SS_OBSERVER", "SS_TAKEN" }) do
  local v = nil;
  pcall(function()
    local f = loadstring and loadstring("return SlotStatus." .. k);
    if f ~= nil then v = f() end
  end);
  print(string.format("  SlotStatus.%-14s = %s", k, tostring(v)));
end

print("")
print("=== 3. 全部 GameConfiguration 参数 ===")
pcall(function()
  for k, v in pairs(GameConfiguration) do
    local s = tostring(v);
    if #s < 60 then print(string.format("  %-28s = %s", tostring(k), s)) end
  end
end);
for _, k in ipairs({ "CITY_STATE_COUNT", "RULESET", "GAME_SPEED_TYPE", "START_ERA",
                     "DIFFICULTY", "MAP_SIZE", "GAME_MODE", "MAX_TURNS", "TURN_LIMIT" }) do
  local ok, v = pcall(function() return GameConfiguration.GetValue(k) end);
  print(string.format("  GetValue(%-18s) = %s", k, tostring(ok and v or "ERR")));
end

print("")
print("=== 4. 地图参数 ===")
for _, k in ipairs({ "MAP_SIZE", "MAP_SCRIPT", "resources", "start", "temperature",
                     "rainfall", "sea_level", "world_age", "MAP_WORLD_AGE" }) do
  local ok, v = pcall(function() return MapConfiguration.GetValue(k) end);
  print(string.format("  %-18s = %s", k, tostring(ok and v or "ERR")));
end

print("")
print("=== 5. 游戏入口方式 / 自动开始 ===")
local em = nil; pcall(function() em = Events.GetGameEntryMethod() end);
print("  GetGameEntryMethod = " .. tostring(em));
local as = false; pcall(function() as = Automation.IsAutoStartEnabled() end);
print("  IsAutoStartEnabled = " .. tostring(as));

print("")
print("=== 6. 玩家 0 详情（主机）===")
local pc0 = PlayerConfigurations[0];
if pc0 ~= nil then
  for _, m in ipairs({ "GetCivilizationTypeName", "GetLeaderTypeName", "GetLeaderName",
                       "GetSlotStatus", "GetCivilizationLevelTypeName", "GetPlayerName",
                       "GetSlotName", "GetHandicapTypeID" }) do
    local ok, v = pcall(function() return pc0[m](pc0) end);
    print(string.format("  %-32s = %s", m, tostring(ok and v or "ERR")));
  end
end
print("=== 完成 ===")
