print("=== slot 15 现状 ===")
local iT = 15
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-24s %s", l, ok and tostring(v) or "ERR")) end
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("GetCities:GetCount", function() return Players[iT]:GetCities():GetCount() end)
chk("单位数", function() local n=0; for _ in Players[iT]:GetUnits():Members() do n=n+1 end; return n end)
pcall(function()
  local n = Players[iT]:GetCities():GetCount()
  for k = 0, n - 1 do
    local c = Players[iT]:GetCities():GetCityByIndex(k)
    if c ~= nil then
      print("  ★★ 城市: " .. tostring(c:GetName()) .. " @ (" .. c:GetX() .. "," .. c:GetY() .. ")  人口 " .. tostring(c:GetPopulation()))
    end
  end
end)
print("")
print("=== 全局：本局所有城邦 ===")
local n = 0
for j = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[j] end); pcall(function() pl = Players[j] end)
  if pc ~= nil and pl ~= nil then
    local lvl, alive = nil, nil
    pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then
      local cn, civ = 0, nil
      pcall(function() cn = pl:GetCities():GetCount() end)
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      n = n + 1
      if n <= 12 then print(string.format("  slot %2d  cities=%d  %s", j, cn, tostring(civ))) end
    end
  end
end
print("  存活城邦共 " .. n .. " 个")