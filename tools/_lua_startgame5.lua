-- ★★★ 开局 v5 —— 正确顺序：设置后【立刻验证】再 Host
print("=== 开局 v5 ===")

print("")
print("=== 1. 设置前：槽位 0 现状 ===")
local pc0 = PlayerConfigurations[0];
if pc0 == nil then print("  ❌ slot0 nil"); return end
local function show(tag)
  local c, l, n, s = "ERR", "ERR", "", "ERR";
  pcall(function() c = pc0:GetCivilizationTypeName() end);
  pcall(function() l = pc0:GetLeaderTypeName() end);
  pcall(function() n = pc0:GetLeaderName() end);
  pcall(function() s = pc0:GetSlotStatus() end);
  print(string.format("  [%s] civ=%s leader=%s name=%s status=%s",
        tag, tostring(c), tostring(l), tostring(n), tostring(s)));
end
show("设置前");

print("")
print("=== 2. 设置文明 / 领袖 / 槽位状态 ===")
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
print("  目标 civ=" .. tostring(sCiv) .. " leader=" .. tostring(sLeader) .. " name=" .. tostring(sLeaderName));

-- ★ 先设领袖（引擎可能要求领袖先于文明）
if sLeader ~= nil then
  local b1 = pcall(function() pc0:SetLeaderTypeName(sLeader) end);
  print("  SetLeaderTypeName ok=" .. tostring(b1));
end
if sCiv ~= nil then
  local b2 = pcall(function() pc0:SetCivilizationTypeName(sCiv) end);
  print("  SetCivilizationTypeName ok=" .. tostring(b2));
end
if sLeaderName ~= nil then
  pcall(function() pc0:SetLeaderName(sLeaderName) end);
end
local b3 = pcall(function() pc0:SetSlotStatus(3) end);      -- 3 = Human
print("  SetSlotStatus(3) ok=" .. tostring(b3));
pcall(function() Network.BroadcastPlayerInfo(0) end);
pcall(function() if Network.BroadcastGameConfig ~= nil then Network.BroadcastGameConfig() end end);

show("设置后");

print("")
print("=== 3. ★ 关键判断：设置是否生效 ===")
local c2, l2 = "ERR", "ERR";
pcall(function() c2 = pc0:GetCivilizationTypeName() end);
pcall(function() l2 = pc0:GetLeaderTypeName() end);
if c2 == nil or c2 == "" or l2 == nil or l2 == "" then
  print("  ❌❌ 设置【没生效】—— 文明/领袖仍为空，Host 必然 early exit");
  print("     可能原因：AdvancedSetup 弹窗的 SetToDefaults 是异步的，把设置冲掉了");
  return;
end
print("  ✅ 设置已生效");

print("")
print("=== 4. Automation + SetGameEntryMethod ===")
pcall(function() Automation.SetAutoStartEnabled(true) end);
pcall(function() Events.SetGameEntryMethod("Create a Game") end);

print("")
print("=== 5. HostGame ===")
local bH = pcall(function() Network.HostGame(ServerType.SERVER_TYPE_NONE) end);
print("  HostGame ok=" .. tostring(bH));

-- ★ Host 之后【立刻】复查（看引擎有没有把它清掉）
print("")
print("=== 6. Host 之后立刻复查 ===")
show("Host后");
print("=== 完成 ===")
