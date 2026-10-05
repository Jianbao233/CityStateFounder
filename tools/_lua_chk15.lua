for _, iT in ipairs({15}) do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[iT] end)
  pcall(function() pl = Players[iT] end)
  print("  ── slot " .. iT .. " ──")
  local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("    %-22s %s", l, ok and tostring(v) or ("ERR:" .. tostring(v):sub(1,40))))
  end
  chk("IsAlive", function() return pl:IsAlive() end)
  chk("GetCivType", function() return pc:GetCivilizationTypeName() end)
  chk("GetLeader", function() return pc:GetLeaderTypeName() end)
  chk("GetCivLevel", function() return pc:GetCivilizationLevelTypeName() end)
  chk("GetSlotStatus", function() return pc:GetSlotStatus() end)
  chk("IsMajor", function() return pl:IsMajor() end)
  chk("IsMinor", function() return pl:IsMinor() end)
  chk("GetCities", function() return pl:GetCities():GetCount() end)
  chk("GetDiplomacy", function() return pl:GetDiplomacy() end)
  chk("GetInfluence", function() return pl:GetInfluence() end)
  chk("GetTreasury", function() return pl:GetTreasury() end)
  chk("GetTechs", function() return pl:GetTechs() end)
  chk("GetCulture", function() return pl:GetCulture() end)
  chk("GetUnits", function() local n=0; for _ in pl:GetUnits():Members() do n=n+1 end; return n end)
end
print("")
print("  === 存活城邦总览 ===")
local n = 0
for j = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[j] end); pcall(function() pl = Players[j] end)
  if pc ~= nil and pl ~= nil then
    local lvl, alive = nil, nil
    pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then
      local civ, cn = nil, 0
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      pcall(function() cn = pl:GetCities():GetCount() end)
      n = n + 1
      print(string.format("    slot %2d 城市=%d %s", j, cn, tostring(civ)))
    end
  end
end
print("  存活城邦 " .. n .. " 个")