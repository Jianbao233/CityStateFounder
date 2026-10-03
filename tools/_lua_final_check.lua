-- 交付前最终取证：把所有"可用/可建"的城邦列全（含我们的 6 个）
print("=== A. 本局城邦总览（只算【已激活】的）===")
local iAlive, iDead, iOursAlive = 0, 0, 0
local tAlive = {}
for i = 0, 63 do
  local p = nil
  pcall(function() p = Players[i] end)
  if p ~= nil then
    local pc = nil
    pcall(function() pc = PlayerConfigurations[i] end)
    if pc ~= nil then
      local civ = nil
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      if civ ~= nil and civ ~= "" then
        local row = nil
        pcall(function() row = GameInfo.Civilizations[civ] end)
        local lvl = nil
        if row ~= nil then pcall(function() lvl = row.StartingCivilizationLevelType end) end
        -- 用遍历匹配（索引取值不可靠）
        local bCS = false
        pcall(function()
          for r in GameInfo.Civilizations() do
            if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
              bCS = true break
            end
          end
        end)
        if bCS then
          local alive, cities = false, 0
          pcall(function() alive = p:IsAlive() end)
          pcall(function() cities = p:GetCities():GetCount() end)
          if alive then
            iAlive = iAlive + 1
            local sName = "?"
            pcall(function()
              for r in GameInfo.Civilizations() do
                if r.CivilizationType == civ then sName = Locale.Lookup(r.Name) break end
              end
            end)
            local bOurs = string.find(civ, "CSF_CS_") ~= nil
            if bOurs then iOursAlive = iOursAlive + 1 end
            tAlive[#tAlive+1] = {i=i, civ=civ, name=sName, cities=cities, ours=bOurs}
          else
            iDead = iDead + 1
          end
        end
      end
    end
  end
end
table.sort(tAlive, function(a,b) return a.i < b.i end)
for _, r in ipairs(tAlive) do
  print(string.format("  slot %2d | %-26s | %-10s | cities=%d %s",
        r.i, r.civ, r.name, r.cities, r.ours and "← ★ 我们的" or ""))
end
print(string.format("  → 已激活城邦 %d 个（其中我们的 %d 个）；未激活 %d 个", iAlive, iOursAlive, iDead))

print("")
print("=== B. 可建列表（休眠态：0 城）===")
local iAvail, iOursAvail = 0, 0
for _, r in ipairs(tAlive) do
  if r.cities == 0 then
    iAvail = iAvail + 1
    if r.ours then iOursAvail = iOursAvail + 1 end
    print(string.format("  可建: %-10s (%s)%s", r.name, r.civ, r.ours and "  ← ★ 我们的" or ""))
  end
end
print(string.format("  → 可建 %d 个（其中我们的 %d 个）", iAvail, iOursAvail))

print("")
print("=== C. 本模组脚本与面板 ===")
print("  ExposedMembers.CSF       = " .. tostring(ExposedMembers ~= nil and ExposedMembers.CSF ~= nil))
print("  ContextPtr(CSF_Panel)    = " .. tostring(ContextPtr ~= nil))
print("  UNIT_CSF_ENVOY 存在       = " .. tostring(GameInfo.Units["UNIT_CSF_ENVOY"] ~= nil))
