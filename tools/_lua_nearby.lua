print("=== 找一个靠近人类单位的城邦，放到旁边 ===")
-- 人类单位位置
local ux, uy = -1, -1
pcall(function()
  for u in Players[0]:GetUnits():Members() do
    local uu = nil
    pcall(function() uu = UnitManager.GetUnit(0, u) end)
    if uu ~= nil then
      local x, y = nil, nil
      pcall(function() x, y = uu:GetX(), uu:GetY() end)
      if x ~= nil and x >= 0 then ux, uy = x, y break end
    end
  end
end)
print("  人类单位在 (" .. tostring(ux) .. "," .. tostring(uy) .. ")")

-- 找一个未激活的城邦槽
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
local iT, sCiv = -1, nil
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
          if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break end
        end
      end)
      if bCS then iT, sCiv = i, civ break end
    end
  end
end
if iT < 0 then print("  没有可激活的槽"); return end
print("  目标: slot " .. iT .. "  " .. sCiv)

-- 在人类单位附近找一个空陆地格
local iX, iY = -1, -1
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
pcall(function()
  for r = 2, 8 do
    for dy = -r, r do
      for dx = -r, r do
        if math.abs(dx) == r or math.abs(dy) == r then
          local x, y = ux + dx, uy + dy
          if x >= 1 and y >= 1 and x < w - 1 and y < h - 1 then
            local plot = Map.GetPlot(x, y)
            if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
               and plot:GetFeatureType() == -1 and plot:IsMountain() == false then
              iX, iY = x, y return
            end
          end
        end
      end
    end
  end
end)
print("  目标格 (" .. iX .. "," .. iY .. ")")
if iX < 0 then print("  找不到合适格"); return end

-- 激活 + 放移民
pcall(function() pm:SetPlayerSlotStatus(iT, 1) end)
pcall(function() pm:InitializePlayer(iT) end)
local alive = nil; pcall(function() alive = Players[iT]:IsAlive() end)
print("  alive = " .. tostring(alive))
local col = nil; pcall(function() col = PlayerConfigurations[iT]:GetColor() end)
print("  GetColor = " .. tostring(col))
local b = pcall(function() UnitManager.InitUnit(iT, "UNIT_SETTLER", iX, iY) end)
print("  放移民 ok=" .. tostring(b))
print(string.format("  ★ 请点下一回合：城邦「%s」应在 (%d,%d) 建城（就在你单位旁边）", sCiv, iX, iY))
