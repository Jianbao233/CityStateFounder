local t = {}
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local civ, st, lvl = nil, nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() st = pc:GetSlotStatus() end)
    pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and civ ~= nil and civ ~= "" then
      local alive = nil; pcall(function() alive = Players[j]:IsAlive() end)
      t[#t+1] = {j, civ, st, alive}
    end
  end
end
print("  城邦槽总数 = " .. #t)
local nInactive = 0
for _, e in ipairs(t) do
  if e[4] ~= true then nInactive = nInactive + 1 end
end
print("  其中【未激活】= " .. nInactive)
print("  ── 前 8 个未激活的 ──")
local k = 0
for _, e in ipairs(t) do
  if e[4] ~= true then
    k = k + 1
    if k <= 8 then print(string.format("    slot %2d  status=%s  %s", e[1], tostring(e[3]), tostring(e[2]))) end
  end
end