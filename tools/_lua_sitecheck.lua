-- 检查 (46,26) 是不是合格城址
local iX, iY = 46, 26
local pl = nil; pcall(function() pl = Map.GetPlot(iX, iY) end)
if pl == nil then print("  ❌ 地块不存在"); return end
print("  地块 (" .. iX .. "," .. iY .. ")")
local function g(l, f) local ok,v = pcall(f); print(string.format("    %-20s %s", l, ok and tostring(v) or "ERR")) end
g("IsWater", function() return pl:IsWater() end)
g("IsMountain", function() return pl:IsMountain() end)
g("GetOwner", function() return pl:GetOwner() end)
g("GetTerrainType", function() return pl:GetTerrainType() end)
g("GetFeatureType", function() return pl:GetFeatureType() end)
g("IsFreshWater", function() return pl:IsFreshWater() end)
g("IsCoastalLand", function() return pl:IsCoastalLand() end)
-- 周围陆地数（半径 3）
local nLand, nWater = 0, 0
for dy = -3, 3 do
  for dx = -3, 3 do
    if dx ~= 0 or dy ~= 0 then
      local p2 = nil; pcall(function() p2 = Map.GetPlot(iX+dx, iY+dy) end)
      if p2 ~= nil then
        local w = true; pcall(function() w = p2:IsWater() end)
        if w then nWater = nWater + 1 else nLand = nLand + 1 end
      end
    end
  end
end
print("    半径3 内 陆地=" .. nLand .. " 水域=" .. nWater)
-- 该城邦有没有移民
local iT = 36
local n = 0
pcall(function()
  for _, u in Players[iT]:GetUnits():Members() do
    local ut, ux, uy = nil, nil, nil
    pcall(function() ut = GameInfo.Units[u:GetType()].UnitType end)
    pcall(function() ux = u:GetX() end); pcall(function() uy = u:GetY() end)
    n = n + 1
    print("    单位: " .. tostring(ut) .. " @ (" .. tostring(ux) .. "," .. tostring(uy) .. ")")
  end
end)
print("  slot 36 单位数 = " .. n)
print("  Cities.GetCityInPlot = " .. tostring(select(2, pcall(function() return Cities.GetCityInPlot(iX, iY) end))))