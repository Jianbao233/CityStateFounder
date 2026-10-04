print("=== 给已激活的 slot 15 放移民 + 补颜色 ===")
local iT = 15

local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-26s %s", l, ok and tostring(v) or "ERR")) end
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("GetColor", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("GetCivType", function() return PlayerConfigurations[iT]:GetCivilizationTypeName() end)

-- ① 补颜色：抄同文明的另一个玩家（若有），否则用官方城邦底色
local sCiv = nil; pcall(function() sCiv = PlayerConfigurations[iT]:GetCivilizationTypeName() end)
local col = nil
for j = 0, 63 do
  if j ~= iT then
    pcall(function()
      if PlayerConfigurations[j]:GetCivilizationTypeName() == sCiv and Players[j]:IsAlive() then
        col = C6FW.GetPlayerColor(PlayerConfigurations[j])
      end
    end)
    if col ~= nil then break end
  end
end
print("  找到同文明颜色 = " .. tostring(col))
if col == nil then col = -1101123981 end   -- 官方城邦底色（之前实测值）
local okc = pcall(function() C6FW.SetPlayerColor(PlayerConfigurations[iT], col) end)
print("  SetPlayerColor(" .. tostring(col) .. ") ok=" .. tostring(okc))
chk("GetColor 复查", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)

-- ② 找一块模组认可的空地
local fValid = ExposedMembers.CSF.IsValidLocation
local w, h = 0, 0; pcall(function() w, h = Map.GetGridSize() end)
local iX, iY = -1, -1
pcall(function()
  for y = 4, h - 5 do
    for x = 4, w - 5 do
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
print("  目标格 (" .. iX .. "," .. iY .. ")")
if iX < 0 then print("  ❌ 找不到"); return end

-- ③ 放移民
local okU, rU = pcall(function() return UnitManager.InitUnit(iT, "UNIT_SETTLER", iX, iY) end)
print("  InitUnit ok=" .. tostring(okU) .. " 返回=" .. tostring(rU))
local n = 0; pcall(function() for _ in Players[iT]:GetUnits():Members() do n = n + 1 end end)
print("  该玩家单位数 = " .. n)

-- ④ 最终体检
print("")
print("=== 最终体检 ===")
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("IsMajor", function() return Players[iT]:IsMajor() end)
chk("SlotStatus", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("GetColor", function() return PlayerConfigurations[iT]:GetColor() end)
chk("GetCivLevel", function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)
chk("GetCities:GetCount", function() return Players[iT]:GetCities():GetCount() end)
chk("GetDiplomacy", function() return Players[iT]:GetDiplomacy() end)
chk("GetInfluence", function() return Players[iT]:GetInfluence() end)
chk("GetTreasury", function() return Players[iT]:GetTreasury() end)
chk("GetTechs", function() return Players[iT]:GetTechs() end)
chk("GetCulture", function() return Players[iT]:GetCulture() end)
print("")
print(string.format("★★★ 请点下一回合：看 (%d,%d) 是否建城、是否崩溃", iX, iY))
print("=== 结束 ===")