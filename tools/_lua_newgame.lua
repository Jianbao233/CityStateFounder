print("=== AH 开局补全 ===")
if Automation ~= nil and Automation.SetAutoStartEnabled ~= nil then
  pcall(function() Automation.SetAutoStartEnabled(true) end)
end
-- 看当前房间状态
if AH_GetRoomState ~= nil then
  local ok, r = pcall(AH_GetRoomState)
  print("  GetRoomState ok=" .. tostring(ok) .. " -> " .. tostring(r))
end
if Network ~= nil then
  local ok1, v1 = pcall(function() return Network.IsInSession() end)
  print("  IsInSession = " .. tostring(ok1 and v1 or "?"))
  local ok2, v2 = pcall(function() return Network.IsHost() end)
  print("  IsHost      = " .. tostring(ok2 and v2 or "?"))
end
-- 设城邦数（此时 PrepareRoom 已跑过）
pcall(function() GameConfiguration.SetValue("CITY_STATE_COUNT", 27) end)
pcall(function() GameConfiguration.SetValue("RULESET", "RULESET_EXPANSION_2") end)
print("  已设 CITY_STATE_COUNT=27 / RULESET=EXPANSION_2")

-- Ready + Start
if AH_Ready ~= nil then
  local ok, err = pcall(AH_Ready)
  print("  AH_Ready ok=" .. tostring(ok) .. " err=" .. tostring(err))
end
if AH_Start ~= nil then
  local ok, err = pcall(AH_Start)
  print("  AH_Start ok=" .. tostring(ok) .. " err=" .. tostring(err))
end
-- 兜底：直接 LaunchGame
if Network ~= nil and Network.LaunchGame ~= nil then
  local ok, err = pcall(function() Network.LaunchGame() end)
  print("  Network.LaunchGame ok=" .. tostring(ok) .. " err=" .. tostring(err))
end
print("=== 完成 ===")
