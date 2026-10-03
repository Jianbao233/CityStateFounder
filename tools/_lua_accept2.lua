-- 验收续：复查城邦状态 + 建副本测试
print("=== 验收续 ===")

print("")
print("=== 1. slot 15 (ANTIOCH) 复查 ===")
local i = 15
local function chk(l, f) local ok,v = pcall(f); print(string.format("  %-30s %s", l, ok and tostring(v) or ("ERR:"..tostring(v)))) end
chk("IsAlive", function() return Players[i]:IsAlive() end)
chk("GetCities():GetCount()", function() return Players[i]:GetCities():GetCount() end)
chk("GetColor", function() return PlayerConfigurations[i]:GetColor() end)
chk("单位数", function()
  local n = 0
  for _ in Players[i]:GetUnits():Members() do n = n + 1 end
  return n
end)
pcall(function()
  for u in Players[i]:GetUnits():Members() do
    print(string.format("    单位: type=%s @ (%s,%s)", tostring(u:GetType()), tostring(u:GetX()), tostring(u:GetY())))
  end
end)
local cap = nil; pcall(function() cap = Players[i]:GetCities():GetCapitalCity() end)
if cap ~= nil then
  pcall(function()
    print(string.format("    首都: %s @ (%s,%s) 人口=%s",
      tostring(Locale.Lookup(cap:GetName())), tostring(cap:GetX()), tostring(cap:GetY()),
      tostring(cap:GetPopulation())))
  end)
end

print("")
print("=== 2. 本局城邦总览 ===")
local tAlive, tDormant = {}, {}
for j = 15, 63 do
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
          if r.CivilizationType == civ
             and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break end
        end
      end)
      if bCS then
        local c = 0; pcall(function() c = p:GetCities():GetCount() end)
        if c > 0 then tAlive[#tAlive+1] = {i=j, civ=civ, n=c}
        else tDormant[#tDormant+1] = {i=j, civ=civ} end
      end
    end
  end
end
print("  已建城: " .. #tAlive .. " 个")
for _, k in ipairs(tAlive) do print(string.format("    slot %2d  %-30s cities=%d", k.i, k.civ, k.n)) end
print("  休眠(0城): " .. #tDormant .. " 个")
for _, k in ipairs(tDormant) do print(string.format("    slot %2d  %s", k.i, k.civ)) end

print("")
print("=== 3. 找【已上场】的城邦，准备建副本 ===")
local iSrc, sSrcCiv = -1, nil
for _, k in ipairs(tAlive) do
  if k.i ~= 15 then iSrc, sSrcCiv = k.i, k.civ break end
end
if iSrc < 0 then
  print("  （还没有已上场的城邦 → 副本测试需要先等城邦建城）")
else
  print(string.format("  副本目标: %s（已上场，slot %d）", sSrcCiv, iSrc))
end
print("=== 结束 ===")
