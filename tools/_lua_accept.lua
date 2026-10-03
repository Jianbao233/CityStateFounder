-- ★★ 验收测试：用 CSF_CreateCityState 模块建一个城邦
print("=== 城邦创建验收 ===")

print("")
print("=== 0. 模块自检 ===")
print("  ExposedMembers.CSF_CreateCityState = " .. type(ExposedMembers and ExposedMembers.CSF_CreateCityState))
if ExposedMembers ~= nil and ExposedMembers.CSF_CreateCityState ~= nil then
  for _, k in ipairs({ "CreateAt", "ActivateSlot", "FindInactiveSlot" }) do
    print("    " .. k .. " = " .. type(ExposedMembers.CSF_CreateCityState[k]))
  end
end
print("  C6FW = " .. type(C6FW))

print("")
print("=== 1. 找一个可激活的城邦槽 ===")
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
print("  PlayerManager = " .. type(pm))
local iT, sCiv, st = -1, nil, nil
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if civ ~= nil and civ ~= "" and alive == false then
      local bCS = false
      pcall(function()
        for r in GameInfo.Civilizations() do
          if r.CivilizationType == civ
             and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break end
        end
      end)
      if bCS then iT, sCiv = i, civ break end
    end
  end
end
if iT < 0 then print("  ❌ 没有可激活的城邦槽"); return end
pcall(function() st = pm:GetSlotStatus(iT) end)
print(string.format("  目标: slot %d  %s  GetSlotStatus=%s", iT, sCiv, tostring(st)))

print("")
print("=== 2. 找一块安全的地（离所有城市远）===")
local tCity = {}
for i = 0, 63 do
  local p = nil; pcall(function() p = Players[i] end)
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
print("  已有城市数 = " .. #tCity)
local function d2(x1,y1,x2,y2) local dx,dy=x1-x2,y1-y2; return dx*dx+dy*dy end
local iX, iY = -1, -1
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
print(string.format("  地图 %dx%d", w, h))
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
          for _, c in ipairs(tCity) do
            if d2(x, y, c.x, c.y) < 25 then ok = false break end
          end
          if ok then iX, iY = x, y; return end
        end
      end
    end
  end
end)
print(string.format("  目标格 (%d,%d)", iX, iY))
if iX < 0 then print("  ❌ 找不到安全地块"); return end

print("")
print("=== 3. 激活（三步公式 + 补色）===")
pcall(function() pm:SetPlayerSlotStatus(iT, 1) end)
pcall(function() pm:InitializePlayer(iT) end)
local alive = nil; pcall(function() alive = Players[iT]:IsAlive() end)
print("  alive = " .. tostring(alive))
if alive ~= true then print("  ❌ 激活失败"); return end
local cAfter = nil; pcall(function() cAfter = PlayerConfigurations[iT]:GetColor() end)
print("  GetColor = " .. tostring(cAfter))

print("")
print("=== 4. 体检（建城前）===")
local function chk(l, f) local ok,v = pcall(f); print(string.format("  %-30s %s", l, ok and tostring(v) or ("ERR:"..tostring(v)))) end
chk("GetColor", function() return PlayerConfigurations[iT]:GetColor() end)
chk("GetCivilizationLevelTypeName", function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)
chk("GetLeaderName", function() return PlayerConfigurations[iT]:GetLeaderName() end)
chk("GetDiplomacy", function() return Players[iT]:GetDiplomacy() end)
chk("GetInfluence", function() return Players[iT]:GetInfluence() end)
chk("IsMajor", function() return Players[iT]:IsMajor() end)
chk("GetCities():GetCount()", function() return Players[iT]:GetCities():GetCount() end)

print("")
print("=== 5. 建城：放移民让引擎自建（T-123 方案）===")
local bRes = false
pcall(function() bRes = true end)
local bUnit = pcall(function() UnitManager.InitUnit(iT, "UNIT_SETTLER", iX, iY) end)
print("  UnitManager.InitUnit ok=" .. tostring(bUnit))

print("")
print("=== 6. 立刻复查 ===")
local cnt = nil; pcall(function() cnt = Players[iT]:GetCities():GetCount() end)
print("  cities = " .. tostring(cnt) .. "（引擎会在它的回合建城，0 是正常的）")
print(string.format("  → 请手动交互：slot %d  %s  @ (%d,%d)", iT, sCiv, iX, iY))
print("=== 结束 ===")
