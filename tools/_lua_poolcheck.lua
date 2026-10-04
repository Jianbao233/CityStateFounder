print("=== 城邦池检查 ===")
local n, t = 0, {}
for r in GameInfo.Civilizations() do
  if r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
    n = n + 1
    if string.find(r.CivilizationType, "CSF_CS_") then t[#t+1] = r.CivilizationType end
  end
end
print("  池子里城邦总数 = " .. n)
print("  我们的 = " .. #t .. " 个")
for _, x in ipairs(t) do print("    " .. x) end
print("")
print("=== 本局玩家槽位里我们的城邦 ===")
for i = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[i] end)
  if pc ~= nil then
    local c, a = nil, nil
    pcall(function() c = pc:GetCivilizationTypeName() end)
    pcall(function() a = Players[i]:IsAlive() end)
    if c ~= nil and string.find(c, "CSF_CS_") then
      local st, col = nil, nil
      pcall(function() st = pc:GetSlotStatus() end)
      pcall(function() col = pc:GetColor() end)
      print(string.format("  slot %2d  %s  alive=%s status=%s color=%s", i, c, tostring(a), tostring(st), tostring(col)))
    end
  end
end