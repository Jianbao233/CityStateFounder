-- 查本局城邦构成 + 候选池（只读）
print("=== 本局城邦构成 ===")
local iTotal, iCustom = 0, 0
for i = 0, 63 do
  local pc = nil
  pcall(function() pc = PlayerConfigurations[i] end)
  if pc ~= nil then
    local sCiv = nil
    pcall(function() sCiv = pc:GetCivilizationTypeName() end)
    if sCiv ~= nil and sCiv ~= "" then
      local row = nil
      pcall(function() row = GameInfo.Civilizations[sCiv] end)
      local sLevel = nil
      if row ~= nil then pcall(function() sLevel = row.StartingCivilizationLevelType end) end
      if sLevel == "CIVILIZATION_LEVEL_CITY_STATE" then
        iTotal = iTotal + 1
        local bOurs = string.find(sCiv, "CSF_CS_") ~= nil
        if bOurs then iCustom = iCustom + 1 end
        print(string.format("  slot %2d  %-28s %s", i, sCiv, bOurs and "← ★ 我们的" or ""))
      end
    end
  end
end
print(string.format("  → 本局城邦 %d 个，其中我们的 %d 个", iTotal, iCustom))

print("")
print("=== 候选池：GameInfo 里有多少城邦文明 ===")
local iCand, iOurs = 0, 0
for row in GameInfo.Civilizations() do
  if row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
    iCand = iCand + 1
    if string.find(tostring(row.CivilizationType), "CSF_CS_") then iOurs = iOurs + 1 end
  end
end
print(string.format("  官方+mod 合计候选 %d 个，其中我们的 %d 个", iCand, iOurs))
print("  ⚠️ 若 iOurs 仍为 0，说明 GameInfo.Civilizations() 的遍历过滤有问题")

print("")
print("=== 逐个确认我们的 6 个（按 CivilizationType 精确比对）===")
local want = {}
for row in GameInfo.Civilizations() do
  local t = tostring(row.CivilizationType)
  if string.find(t, "CSF_CS_") then want[t] = row end
end
local n = 0
for t, row in pairs(want) do
  n = n + 1
  print(string.format("  %-26s level=%s", t, tostring(row.StartingCivilizationLevelType)))
end
print("  → GameInfo 里找到 " .. n .. " 个")

print("")
print("=== 开局设置里的城邦数量 ===")
local ok, v = pcall(function() return GameConfiguration.GetValue("CITY_STATE_COUNT") end)
print("  CITY_STATE_COUNT = " .. (ok and tostring(v) or "(取不到)"))
local ok2, ms = pcall(function() return GameConfiguration.GetValue("MAP_SIZE") end)
print("  MAP_SIZE         = " .. (ok2 and tostring(ms) or "(取不到)"))
