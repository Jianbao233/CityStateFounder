print("=== 测试 ⑥⑦ 修复 ===")
local iT = -1
for i = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[i] end); pcall(function() pl = Players[i] end)
  if pc ~= nil and pl ~= nil then
    local civ, alive, st = nil, nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    pcall(function() st = pc:GetSlotStatus() end)
    if civ ~= nil and civ ~= "" and alive == false and st == 5 then
      local bCS = false
      pcall(function() for r in GameInfo.Civilizations() do
        if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then bCS = true break end
      end end)
      if bCS then iT = i break end
    end
  end
end
print("  目标 slot = " .. tostring(iT))
if iT < 0 then print("  无可用槽"); return end
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("    %-24s %s", l, ok and tostring(v) or "ERR")) end

print("  ① ActivatePlayer")
local ok1, r1 = pcall(C6FW.ActivatePlayer, iT); print("    ok=" .. tostring(ok1) .. " 返回=" .. tostring(r1))
print("  ② SetPlayerSlotStatus(1)")
local pm = nil; pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm then pcall(function() pm:SetPlayerSlotStatus(iT, 1) end) end
print("  ③ SetAlive(1)")
pcall(C6FW.SetAlive, iT, 1)
chk("IsAlive", function() return Players[iT]:IsAlive() end)

print("  ④ 找地（用模组校验，且远离地图边缘）")
local fValid = ExposedMembers.CSF.IsValidLocation
local w, h = 0, 0; pcall(function() w, h = Map.GetGridSize() end)
local iX, iY = -1, -1
pcall(function()
  for y = 8, h - 9 do
    for x = 8, w - 9 do
      local plot = Map.GetPlot(x, y)
      if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
         and plot:GetFeatureType() == -1 and plot:IsMountain() == false then
        local land = 0
        for d = 0, 5 do
          local nb = Map.GetAdjacentPlot(x, y, d)
          if nb ~= nil and nb:IsWater() == false then land = land + 1 end
        end
        if land >= 4 then
          local okv, bv = pcall(fValid, x, y, nil)
          if okv and bv == true then iX, iY = x, y; return end
        end
      end
    end
  end
end)
print("    目标格 (" .. iX .. "," .. iY .. ")  ← 远离边缘（8 <= x,y）")

print("  ⑤ ★ UnitManager.InitUnit")
if iX > 0 then
  local okU, rU = pcall(function() return UnitManager.InitUnit(iT, "UNIT_SETTLER", iX, iY) end)
  print("    ok=" .. tostring(okU) .. " 返回=" .. tostring(rU))
  local n = 0; pcall(function() for _ in Players[iT]:GetUnits():Members() do n = n + 1 end end)
  print("    该玩家单位数 = " .. n)
end
print("  ✅ 走到这里说明没崩")