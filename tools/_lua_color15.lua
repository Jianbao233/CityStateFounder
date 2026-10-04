print("=== 给 slot 15 补颜色 ===")
local iT = 15
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-28s %s", l, ok and tostring(v) or "ERR")) end
chk("GetColor(前)", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("API GetColor(前)", function() return PlayerConfigurations[iT]:GetColor() end)
chk("CivType", function() return PlayerConfigurations[iT]:GetCivilizationTypeName() end)

-- ① 先看场上别的城邦有没有颜色可抄
print("  ── 场上城邦的颜色 ──")
local nFound = 0
for j = 0, 63 do
  if j ~= iT then
    local lvl, col = nil, nil
    pcall(function() lvl = PlayerConfigurations[j]:GetCivilizationLevelTypeName() end)
    pcall(function() col = C6FW.GetPlayerColor(PlayerConfigurations[j]) end)
    if lvl == "CIVILIZATION_LEVEL_CITY_STATE" then
      local alive = nil; pcall(function() alive = Players[j]:IsAlive() end)
      print(string.format("    slot %2d alive=%-5s color=%s", j, tostring(alive), tostring(col)))
      nFound = nFound + 1
      if nFound >= 6 then break end
    end
  end
end

-- ② 调模组自己的补色函数
local f = ExposedMembers.CSF.ApplyCityStateColor
print("  ApplyCityStateColor = " .. type(f))
if f ~= nil then
  local ok, r = pcall(f, iT)
  print("  调用 ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
end
chk("GetColor(后)", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("API GetColor(后)", function() return PlayerConfigurations[iT]:GetColor() end)