-- 挑第一个未激活的城邦槽
local iTarget = nil
for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local civ, lvl = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and civ ~= nil and civ ~= "" then
      local alive = nil; pcall(function() alive = Players[j]:IsAlive() end)
      if alive ~= true then iTarget = j; break end
    end
  end
end
print("  目标槽 = " .. tostring(iTarget))
if iTarget == nil then print("  没有未激活的"); return end
local pc = PlayerConfigurations[iTarget]
local civ = nil; pcall(function() civ = pc:GetCivilizationTypeName() end)
print("  目标文明 = " .. tostring(civ))
local ok, r = pcall(C6FW.ActivatePlayer, iTarget)
print("  C6FW.ActivatePlayer ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
local ok2, r2 = pcall(C6FW.SetAlive, iTarget, 1)
print("  C6FW.SetAlive ok=" .. tostring(ok2) .. " 返回=" .. tostring(r2))
local alive = nil; pcall(function() alive = Players[iTarget]:IsAlive() end)
print("  IsAlive = " .. tostring(alive))
print("  ★ 脚本正常结束 = 没崩")