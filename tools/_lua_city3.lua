local ok, t = pcall(function() return Game.GetCurrentGameTurn() end)
print("  当前回合 = " .. tostring(t))
local n, nCity = 0, 0
for j = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[j] end); pcall(function() pl = Players[j] end)
  if pc ~= nil and pl ~= nil then
    local lvl, alive = nil, nil
    pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then
      local civ, cn, uni = nil, 0, 0
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      pcall(function() cn = pl:GetCities():GetCount() end)
      pcall(function() for _ in pl:GetUnits():Members() do uni = uni + 1 end end)
      n = n + 1; nCity = nCity + cn
      print(string.format("  slot %2d  城市=%d  单位=%d  %s", j, cn, uni, tostring(civ)))
      pcall(function()
        for k = 0, cn - 1 do
          local c = pl:GetCities():GetCityByIndex(k)
          if c ~= nil then print(string.format("      ★ %s @ (%d,%d) 人口 %d", tostring(c:GetName()), c:GetX(), c:GetY(), c:GetPopulation())) end
        end
      end)
    end
  end
end
print("  存活城邦 " .. n .. " 个，城市总数 " .. nCity)