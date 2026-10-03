-- 探测 AgentHost 的 AH_* API 是否可用（在主菜单状态执行）
print("=== AgentHost API 探测 ===")
local names = {
  "AH_SelfTest","AH_SetParam","AH_ListCivs","AH_SelectCiv","AH_SetSlot",
  "AH_Ready","AH_Start","AH_LeaveRoom","AH_HostRoom","AH_HostAndStart",
  "AH_GetRoomState","AH_WriteSnapshot"
}
local n = 0
for _, k in ipairs(names) do
  local f = rawget(_G, k)
  if type(f) == "function" then n = n + 1; print("  ✅ " .. k) else print("  ❌ " .. k) end
end
print("  → 可用 " .. n .. " / " .. #names)

print("")
print("=== 其它关键 API ===")
print("  Automation                = " .. type(Automation))
print("  Automation.SetAutoStartEnabled = " .. type(Automation and Automation.SetAutoStartEnabled))
print("  Network.HostGame          = " .. type(Network and Network.HostGame))
print("  ServerType.SERVER_TYPE_NONE = " .. tostring(ServerType and ServerType.SERVER_TYPE_NONE))
print("  GameConfiguration         = " .. type(GameConfiguration))
print("  MapConfiguration          = " .. type(MapConfiguration))
print("  PlayerConfigurations      = " .. type(PlayerConfigurations))
print("  OnResumeGame              = " .. type(rawget(_G,"OnResumeGame")))
print("  OnLANGame                 = " .. type(rawget(_G,"OnLANGame")))
print("  GameModeTypes             = " .. type(GameModeTypes))

print("")
print("=== 当前配置快照 ===")
if GameConfiguration ~= nil then
  for _, k in ipairs({"RULESET","MAP_SIZE","MAP_SCRIPT","CITY_STATE_COUNT","GAME_NAME","GAME_SPEED_TYPE"}) do
    local ok, v = pcall(function() return GameConfiguration.GetValue(k) end)
    print(string.format("  %-20s = %s", k, ok and tostring(v) or "(取不到)"))
  end
end
