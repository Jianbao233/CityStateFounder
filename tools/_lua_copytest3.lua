print("=== 制造副本：CIVILIZATION_VILNIUS ===")
local sCiv = "CIVILIZATION_VILNIUS"

print("")
print("=== 1. 先看 PRESLAV 现在有几个玩家 ===")
local tBefore = {}
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local c, a = nil, nil
    pcall(function() c = pc:GetCivilizationTypeName() end)
    pcall(function() a = Players[j]:IsAlive() end)
    if c == sCiv then
      local n = 0; pcall(function() n = Players[j]:GetCities():GetCount() end)
      tBefore[#tBefore+1] = {i=j, alive=a, cities=n}
      print(string.format("  slot %2d  alive=%-5s cities=%d", j, tostring(a), n))
    end
  end
end
print("  → 共 " .. #tBefore .. " 个")

print("")
print("=== 2. 找一块安全的地（离所有城市远）===")
local tCity = {}
for j = 0, 63 do
  local p = nil; pcall(function() p = Players[j] end)
  if p ~= nil then
    local a = nil; pcall(function() a = p:IsAlive() end)
    if a == true then
      pcall(function()
        local cs = p:GetCities()
        if cs ~= nil then for c in cs() do tCity[#tCity+1] = {x=c:GetX(), y=c:GetY()} end end
      end)
    end
  end
end
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
          for _, c in ipairs(tCity) do if d2(x, y, c.x, c.y) < 25 then okp = false break end end
          if okp then iX, iY = x, y; return end
        end
      end
    end
  end
end)
print(string.format("  已有城市 %d 个，目标格 (%d,%d)", #tCity, iX, iY))
if iX < 0 then print("  ❌ 找不到地块"); return end

print("")
print("=== 3. ★ 调 FoundCityStateByCiv（应走【副本分支】）===")
local f = ExposedMembers.CSF.FoundCityStateByCiv
local ok, a, b, c, d = pcall(f, sCiv, iX, iY, nil, nil)
print("  ok=" .. tostring(ok) .. "  返回=" .. tostring(a) .. ", " .. tostring(b) ..
      ", " .. tostring(c) .. ", " .. tostring(d))

print("")
print("=== 4. 复查：PRESLAV 现在有几个玩家 ===")
local tAfter = {}
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local cv, al = nil, nil
    pcall(function() cv = pc:GetCivilizationTypeName() end)
    pcall(function() al = Players[j]:IsAlive() end)
    if cv == sCiv and al == true then
      local n, col, mk, sf = 0, nil, nil, nil
      pcall(function() n = Players[j]:GetCities():GetCount() end)
      pcall(function() col = pc:GetColor() end)
      pcall(function() mk = Game:GetProperty("CSF_CopyOf_" .. tostring(j)) end)
      pcall(function() sf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
      tAfter[#tAfter+1] = {i=j, n=n, col=col, mk=mk, sf=sf}
    end
  end
end
print("  PRESLAV 存活玩家 " .. #tAfter .. " 个:")
for _, k in ipairs(tAfter) do
  print(string.format("    slot %2d  cities=%d  color=%s  副本标记=%s  后缀=%s",
        k.i, k.n, tostring(k.col), tostring(k.mk), tostring(k.sf)))
end
if #tAfter >= 2 then
  print("  ✅✅ 同一个文明有两个玩家 —— 【可重复】成立！")
else
  print("  ⚠️ 只有一个 —— 副本没建出来（看上面的 [CSF] 日志找原因）")
end
print("=== 结束 ===")