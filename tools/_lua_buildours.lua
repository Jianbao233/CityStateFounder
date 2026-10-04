print("=== 建我们的城邦 CSF_CS_01 ===")
local sCiv = "CIVILIZATION_CSF_CS_01"

-- 用模组自己的 IsValidLocation 挑地
local fValid = ExposedMembers.CSF.IsValidLocation
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
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
print(string.format("  目标格 (%d,%d)", iX, iY))
if iX < 0 then print("  ❌ 找不到合法格"); return end

print("")
print("=== 调 FoundCityStateByCiv ===")
local f = ExposedMembers.CSF.FoundCityStateByCiv
local ok, a, b, c, d = pcall(f, sCiv, iX, iY, nil, nil)
print("  ok=" .. tostring(ok) .. "  返回=" .. tostring(a) .. ", " .. tostring(b) ..
      ", " .. tostring(c) .. ", " .. tostring(d))

print("")
print("=== 复查 ===")
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local cv, al = nil, nil
    pcall(function() cv = pc:GetCivilizationTypeName() end)
    pcall(function() al = Players[j]:IsAlive() end)
    if cv == sCiv and al == true then
      local cn, col, st, lvl = 0, nil, nil, nil
      pcall(function() cn = Players[j]:GetCities():GetCount() end)
      pcall(function() col = pc:GetColor() end)
      pcall(function() st = pc:GetSlotStatus() end)
      pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
      print(string.format("  slot %2d  alive=true cities=%d status=%s color=%s level=%s",
            j, cn, tostring(st), tostring(col), tostring(lvl)))
    end
  end
end
print("=== 结束 ===")