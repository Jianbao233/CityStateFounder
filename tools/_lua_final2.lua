print("=== 补色 + 放移民（slot 15）===")
local iT = 15
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-26s %s", l, ok and tostring(v) or "ERR")) end
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("GetColor(前)", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)

-- ★ 调模组自己的补色（已修 -1 判空 + 抄同场城邦兜底）
local f = ExposedMembers.CSF.ApplyCityStateColor
print("  ApplyCityStateColor = " .. type(f))
if f ~= nil then
  local ok, r = pcall(f, iT)
  print("  调用 ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
end
chk("GetColor(后)", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("GetColor(API)", function() return PlayerConfigurations[iT]:GetColor() end)

-- 放移民
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
          local nb = Map:GetAdjacentPlot(x, y, d)
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
if iX > 0 then
  local okU, rU = pcall(function() return UnitManager.InitUnit(iT, "UNIT_SETTLER", iX, iY) end)
  print("  InitUnit ok=" .. tostring(okU) .. " 返回=" .. tostring(rU))
end
print("")
print("=== 最终体检 ===")
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("IsMajor", function() return Players[iT]:IsMajor() end)
chk("SlotStatus", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("GetColor", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("GetCivLevel", function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)
chk("GetCivType", function() return PlayerConfigurations[iT]:GetCivilizationTypeName() end)
chk("GetCities", function() return Players[iT]:GetCities():GetCount() end)
print(string.format("★★★ 请点下一回合：看 (%d,%d) 是否建城、是否崩溃、旗标有没有颜色", iX, iY))