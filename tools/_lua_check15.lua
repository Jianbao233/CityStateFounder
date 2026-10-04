local iT = 15
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-24s %s", l, ok and tostring(v) or "ERR")) end
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("GetCities:GetCount", function() return Players[iT]:GetCities():GetCount() end)
chk("GetColor", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("SlotStatus", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("GetCivType", function() return PlayerConfigurations[iT]:GetCivilizationTypeName() end)
chk("单位数", function() local n=0; for _ in Players[iT]:GetUnits():Members() do n=n+1 end; return n end)
local ok, t = pcall(function() return Game.GetCurrentGameTurn() end)
print("  当前回合 = " .. tostring(t))
-- 有城市的话报名字和坐标
pcall(function()
  local n = Players[iT]:GetCities():GetCount()
  for k = 0, n - 1 do
    local c = Players[iT]:GetCities():GetCityByIndex(k)
    if c ~= nil then print("  城市: " .. tostring(c:GetName()) .. " @ (" .. c:GetX() .. "," .. c:GetY() .. ") 人口 " .. tostring(c:GetPopulation())) end
  end
end)