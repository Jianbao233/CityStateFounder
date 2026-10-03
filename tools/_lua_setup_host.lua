-- ★ 在 AdvancedSetup 界面里设参数并开局
-- 前提：OnAdvancedSetup() 已调用，AdvancedSetup 状态已存在（state 37）
print("=== AdvancedSetup：设参数 + 开局 ===")

print("")
print("=== 1. 当前参数 ===")
local tShow = { "CITY_STATE_COUNT", "RULESET", "GAME_SPEED", "START_ERA", "DIFFICULTY" };
for _, k in ipairs(tShow) do
  local ok, v = pcall(function() return GameConfiguration.GetValue(k) end);
  print(string.format("  %-20s = %s", k, tostring(ok and v or "ERR")));
end
for _, k in ipairs({ "MAP_SIZE", "MAP_SCRIPT" }) do
  local ok, v = pcall(function() return MapConfiguration.GetValue(k) end);
  print(string.format("  %-20s = %s", k, tostring(ok and v or "ERR")));
end

print("")
print("=== 2. 把城邦数拉高（目标 22）===")
local iWant = 22;
local b1 = pcall(function() GameConfiguration.SetValue("CITY_STATE_COUNT", iWant) end);
local v1 = nil; pcall(function() v1 = GameConfiguration.GetValue("CITY_STATE_COUNT") end);
print("  SetValue(CITY_STATE_COUNT," .. iWant .. ") ok=" .. tostring(b1) .. "  现在=" .. tostring(v1));

-- 确保规则集是资料片2
local b2 = pcall(function() GameConfiguration.SetValue("RULESET", "RULESET_EXPANSION_2") end);
print("  SetValue(RULESET, EXPANSION_2) ok=" .. tostring(b2));

print("")
print("=== 3. 玩家槽位状态 ===")
local iHuman = 0;
for i = 0, 12 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[i] end);
  if pc ~= nil then
    local civ, ldr, st = nil, nil, nil;
    pcall(function() civ = pc:GetCivilizationTypeName() end);
    pcall(function() ldr = pc:GetLeaderTypeName() end);
    pcall(function() st = pc:GetSlotStatus() end);
    if civ ~= nil and civ ~= "" then
      print(string.format("  slot %2d  civ=%-28s leader=%-24s status=%s",
            i, tostring(civ), tostring(ldr), tostring(st)));
    end
  end
end

print("")
print("=== 4. ★ 开局：Network.HostGame(SERVER_TYPE_NONE) ===")
local bH = pcall(function() Network.HostGame(ServerType.SERVER_TYPE_NONE) end);
print("  HostGame ok=" .. tostring(bH));
print("=== 完成 ===")
