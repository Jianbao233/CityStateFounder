print("=== 回合与城邦状态 ===")
local t = nil; pcall(function() t = Game.GetCurrentGameTurn() end)
print("  当前回合 = " .. tostring(t))
local nCity, nDormant = 0, 0
for j = 0, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[j] end)
  pcall(function() pc = PlayerConfigurations[j] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if alive == true and civ ~= nil and civ ~= "" then
      local bCS = false
      pcall(function()
        for r in GameInfo.Civilizations() do
          if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break end
        end
      end)
      if bCS then
        local c = 0; pcall(function() c = p:GetCities():GetCount() end)
        if c > 0 then nCity = nCity + 1 else nDormant = nDormant + 1 end
      end
    end
  end
end
print("  已建城的城邦 = " .. nCity .. "   休眠 = " .. nDormant)
-- 列出已建城的
for j = 0, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[j] end)
  pcall(function() pc = PlayerConfigurations[j] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if alive == true and civ ~= nil and civ ~= "" then
      local c = 0; pcall(function() c = p:GetCities():GetCount() end)
      if c > 0 then
        local cap = nil; pcall(function() cap = p:GetCities():GetCapitalCity() end)
        if cap ~= nil then
          print(string.format("    slot %2d  %-30s  %s @ (%s,%s)",
            j, civ, tostring(Locale.Lookup(cap:GetName())), tostring(cap:GetX()), tostring(cap:GetY())))
        end
      end
    end
  end
end
