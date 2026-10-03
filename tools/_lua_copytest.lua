-- ★★ 测「可重复」：对【已上场】的城邦建副本
print("=== 副本测试 ===")

print("")
print("=== 1. 找一个已上场的城邦 ===")
local iSrc, sSrcCiv = -1, nil
for j = 0, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[j] end)
  pcall(function() pc = PlayerConfigurations[j] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if alive == true and civ ~= nil and civ ~= "" and j ~= 15 then
      local bCS = false
      pcall(function()
        for r in GameInfo.Civilizations() do
          if r.CivilizationType == civ
             and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break end
        end
      end)
      if bCS then
        local c = 0; pcall(function() c = p:GetCities():GetCount() end)
        if c > 0 then iSrc, sSrcCiv = j, civ break end
      end
    end
  end
end
if iSrc < 0 then print("  ❌ 还没有已上场的城邦"); return end
print(string.format("  目标: %s（slot %d，已建城）", sSrcCiv, iSrc))
local c0 = nil; pcall(function() c0 = PlayerConfigurations[iSrc]:GetColor() end)
print("  源城邦颜色 = " .. tostring(c0))

print("")
print("=== 2. 找一块安全的地 ===")
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
          local ok = true
          for _, c in ipairs(tCity) do if d2(x, y, c.x, c.y) < 25 then ok = false break end end
          if ok then iX, iY = x, y; return end
        end
      end
    end
  end
end)
print(string.format("  已有城市 %d 个，目标格 (%d,%d)", #tCity, iX, iY))
if iX < 0 then print("  ❌ 找不到安全地块"); return end

print("")
print("=== 3. ★ 调 FoundCityStateByCiv（应走副本分支）===")
local f = ExposedMembers.CSF.FoundCityStateByCiv
print("  函数 = " .. type(f))
local ok, r1, r2, r3, r4 = pcall(f, sSrcCiv, iX, iY, nil, nil)
print("  ok=" .. tostring(ok) .. "  返回=" .. tostring(r1) .. ", " .. tostring(r2) ..
      ", " .. tostring(r3) .. ", " .. tostring(r4))

print("")
print("=== 4. 复查：是否出现了副本 ===")
local tFound = {}
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = Players[j]:IsAlive() end)
    if civ == sSrcCiv and alive == true then
      local c = 0; pcall(function() c = Players[j]:GetCities():GetCount() end)
      local col = nil; pcall(function() col = pc:GetColor() end)
      local mark = nil
      pcall(function() mark = Game:GetProperty("CSF_CopyOf_" .. tostring(j)) end)
      local suf = nil
      pcall(function() suf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
      tFound[#tFound+1] = {i=j, cities=c, color=col, mark=mark, suf=suf}
    end
  end
end
print("  使用 " .. sSrcCiv .. " 的玩家: " .. #tFound .. " 个")
for _, k in ipairs(tFound) do
  print(string.format("    slot %2d  cities=%d  color=%s  副本标记=%s  后缀=%s",
        k.i, k.cities, tostring(k.color), tostring(k.mark), tostring(k.suf)))
end
if #tFound >= 2 then
  print("  ✅✅ 同一个文明有两个玩家 —— 「可重复」成立！")
else
  print("  ⚠️ 只有一个 —— 副本没建出来")
end
print("=== 结束 ===")
