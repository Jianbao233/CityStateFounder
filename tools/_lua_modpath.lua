-- ★★ 用【模组自己的路径】建城邦（不用我那套 SetPlayerSlotStatus+InitializePlayer）
print("=== 模组正规路径建邦测试 ===")

print("")
print("=== 1. 模组的休眠城邦列表 ===")
local fGet = ExposedMembers.CSF.GetDormantCityStates
print("  GetDormantCityStates = " .. type(fGet))
local tD = nil
local ok1, r1 = pcall(fGet)
print("  调用 ok=" .. tostring(ok1) .. "  返回类型=" .. type(r1))
tD = r1
if type(tD) == "table" then
  print("  休眠城邦 " .. #tD .. " 个:")
  for i, k in ipairs(tD) do
    if type(k) == "table" then
      print(string.format("    [%d] ID=%s Civ=%s", i, tostring(k.ID), tostring(k.Civ)))
    else
      print(string.format("    [%d] %s", i, tostring(k)))
    end
  end
else
  print("  ⚠️ 不是 table，是 " .. type(tD))
end

print("")
print("=== 2. 可建城邦列表（面板用的那个）===")
local fF = ExposedMembers.CSF.GetFoundableCityStates
if fF ~= nil then
  local ok2, r2 = pcall(fF)
  print("  调用 ok=" .. tostring(ok2) .. "  类型=" .. type(r2))
  if type(r2) == "table" then
    print("  可建 " .. #r2 .. " 个:")
    local n = 0
    for i, k in ipairs(r2) do
      n = n + 1
      if n <= 12 then
        if type(k) == "table" then
          print(string.format("    [%d] Civ=%s ID=%s", i, tostring(k.Civ or k.CivilizationType), tostring(k.ID)))
        else print(string.format("    [%d] %s", i, tostring(k))) end
      end
    end
  end
end

print("")
print("=== 3. 选一个目标 + 找安全地块 ===")
local sTarget = nil
if type(tD) == "table" and #tD > 0 and type(tD[1]) == "table" then
  sTarget = tD[1].Civ
end
if sTarget == nil then
  local fP = ExposedMembers.CSF.GetPool
  if fP ~= nil then
    local ok3, r3 = pcall(fP)
    if type(r3) == "table" and #r3 > 0 then sTarget = r3[1].CivilizationType or r3[1].Civ end
  end
end
print("  目标文明 = " .. tostring(sTarget))
if sTarget == nil then print("  ❌ 拿不到目标文明"); return end

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
          for _, c in ipairs(tCity) do if d2(x, y, c.x, c.y) < 16 then okp = false break end end
          if okp then iX, iY = x, y; return end
        end
      end
    end
  end
end)
print(string.format("  已有城市 %d 个，目标格 (%d,%d)", #tCity, iX, iY))
if iX < 0 then print("  ❌ 找不到地块"); return end

print("")
print("=== 4. ★ 调模组正规路径 FoundCityStateByCiv ===")
local f = ExposedMembers.CSF.FoundCityStateByCiv
local ok4, a, b, c, d = pcall(f, sTarget, iX, iY, nil, nil)
print("  ok=" .. tostring(ok4) .. "  返回=" .. tostring(a) .. ", " .. tostring(b) ..
      ", " .. tostring(c) .. ", " .. tostring(d))

print("")
print("=== 5. 复查 ===")
local iNew = nil
if type(c) == "number" then iNew = c end
if iNew == nil then
  for j = 0, 63 do
    local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
      local civ, alive = nil, nil
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      pcall(function() alive = Players[j]:IsAlive() end)
      if civ == sTarget and alive == true then iNew = j break end
    end
  end
end
if iNew ~= nil then
  local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-30s %s", l, ok and tostring(v) or ("ERR:"..tostring(v)))) end
  print("  新玩家 slot = " .. tostring(iNew))
  chk("IsAlive", function() return Players[iNew]:IsAlive() end)
  chk("GetColor", function() return PlayerConfigurations[iNew]:GetColor() end)
  chk("GetCivilizationLevelTypeName", function() return PlayerConfigurations[iNew]:GetCivilizationLevelTypeName() end)
  chk("GetCities():GetCount()", function() return Players[iNew]:GetCities():GetCount() end)
  chk("GetDiplomacy", function() return Players[iNew]:GetDiplomacy() end)
  chk("GetInfluence", function() return Players[iNew]:GetInfluence() end)
  print(string.format("  ★ 请点下一回合，然后看 slot %d（%s）@ (%d,%d) 是否建城且不崩", iNew, sTarget, iX, iY))
end
print("=== 结束 ===")
