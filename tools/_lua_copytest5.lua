print("=== 制造 VILNIUS 副本 v3（用模组自己的 IsValidLocation 挑地）===")
local sCiv = "CIVILIZATION_VILNIUS"
local fValid = ExposedMembers.CSF.IsValidLocation
print("  IsValidLocation = " .. type(fValid))
if fValid == nil then print("  ❌ 拿不到"); return end

local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
local iX, iY = -1, -1
local nTried, nReasons = 0, {}
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
          nTried = nTried + 1
          local okv, bv, sv = pcall(fValid, x, y, nil)
          if okv and bv == true then iX, iY = x, y; return end
          if nTried <= 5 then
            nReasons[#nReasons+1] = string.format("(%d,%d)->%s", x, y, tostring(sv))
          end
        end
      end
    end
  end
end)
print("  试过 " .. nTried .. " 格，前几个的拒绝原因: " .. table.concat(nReasons, "  "))
print(string.format("  ✅ 模组认可的目标格 = (%d,%d)", iX, iY))
if iX < 0 then print("  ❌ 找不到任何合法格"); return end

print("")
print("=== 调 FoundCityStateByCiv（副本分支）===")
local f = ExposedMembers.CSF.FoundCityStateByCiv
local ok, a, b, c, d = pcall(f, sCiv, iX, iY, nil, nil)
print("  ok=" .. tostring(ok) .. "  返回=" .. tostring(a) .. ", " .. tostring(b) ..
      ", " .. tostring(c) .. ", " .. tostring(d))

print("")
print("=== 复查 ===")
local n = 0
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local cv, al = nil, nil
    pcall(function() cv = pc:GetCivilizationTypeName() end)
    pcall(function() al = Players[j]:IsAlive() end)
    if cv == sCiv and al == true then
      local cn, col, sf = 0, nil, nil
      pcall(function() cn = Players[j]:GetCities():GetCount() end)
      pcall(function() col = pc:GetColor() end)
      pcall(function() sf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
      n = n + 1
      print(string.format("  slot %2d  cities=%d  color=%s  后缀=%s", j, cn, tostring(col), tostring(sf)))
    end
  end
end
if n >= 2 then print("  ✅✅ 【可重复】成立！") else print("  ⚠️ 副本仍未建出") end
print("=== 结束 ===")