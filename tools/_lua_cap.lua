print("  C6FW              = " .. type(C6FW))
print("  ExposedMembers.CSF= " .. type(ExposedMembers.CSF))
for _, k in ipairs({"FindFoundLocation","IsValidLocation","FoundCityStateByCiv","GetFoundableCityStates","GetDormantCityStates","ActivateCityState","ApplyCityStateColor","GetPool"}) do
  print(string.format("    %-22s %s", k, type(ExposedMembers.CSF[k])))
end
print("")
print("  === 场上城邦 ===")
local n = 0
for j = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[j] end); pcall(function() pl = Players[j] end)
  if pc ~= nil and pl ~= nil then
    local lvl, alive = nil, nil
    pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then
      local civ, st, cn = nil, nil, 0
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      pcall(function() st = pc:GetSlotStatus() end)
      pcall(function() cn = pl:GetCities():GetCount() end)
      n = n + 1
      print(string.format("    slot %2d status=%s cities=%d %s", j, tostring(st), cn, tostring(civ)))
    end
  end
end
print("    共 " .. n .. " 个存活城邦")
print("")
print("  === 休眠城邦（可复用的）===")
local t = nil
pcall(function() t = ExposedMembers.CSF.GetDormantCityStates() end)
if type(t) == "table" then
  print("    休眠 " .. #t .. " 个")
  for i, e in ipairs(t) do
    if i <= 6 then
      if type(e) == "table" then
        print(string.format("      [%d] ID=%s Civ=%s", i, tostring(e.ID), tostring(e.Civ)))
      else print("      [" .. i .. "] " .. tostring(e)) end
    end
  end
else print("    拿不到") end