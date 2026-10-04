print("=== 制造 VILNIUS 副本 v2（地块离本体足够远）===")
local sCiv = "CIVILIZATION_VILNIUS"

-- ① 本体位置
local tCity = {}
for j = 0, 63 do
  local p = nil; pcall(function() p = Players[j] end)
  if p ~= nil then
    local a = nil; pcall(function() a = p:IsAlive() end)
    if a == true then
      pcall(function()
        local n = p:GetCities():GetCount()
        for k = 0, n - 1 do
          local c = p:GetCities():GetCityByIndex(k)
          if c ~= nil then tCity[#tCity+1] = {x=c:GetX(), y=c:GetY()} end
        end
      end)
    end
  end
end
print("  扫到城市 " .. #tCity .. " 个")
for _, c in ipairs(tCity) do print(string.format("    (%d,%d)", c.x, c.y)) end

-- ② 找一块离所有城市 >= 8 格的地
local function d2(x1,y1,x2,y2) local dx,dy=x1-x2,y1-y2; return dx*dx+dy*dy end
local iX, iY = -1, -1
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
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
          local okp = true
          for _, c in ipairs(tCity) do if d2(x, y, c.x, c.y) < 64 then okp = false break end end
          if okp then iX, iY = x, y; return end
        end
      end
    end
  end
end)
print(string.format("  目标格 (%d,%d)（离所有城市 >= 8 格）", iX, iY))
if iX < 0 then print("  ❌ 找不到"); return end

-- ③ 用模组的合法性检查先验一遍
local fValid = ExposedMembers.CSF.IsValidLocation
if fValid ~= nil then
  local okv, bv, sv = pcall(fValid, iX, iY, nil)
  print("  IsValidLocation ok=" .. tostring(okv) .. " 合法=" .. tostring(bv) .. " 原因=" .. tostring(sv))
  if bv ~= true then print("  ⚠️ 模组说这格不合法，换一格再试"); return end
end

-- ④ 调副本
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