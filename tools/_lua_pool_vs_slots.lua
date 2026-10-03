-- ★ 关键诊断：池子里的城邦 vs 玩家槽位 —— 到底有没有"没槽位"的城邦？
print("=== 城邦池子 vs 玩家槽位 ===")

-- ── 1. 列出 GameInfo 里所有城邦文明 ─────────────────────────────────────
local tPool = {}
for r in GameInfo.Civilizations() do
  if r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
    tPool[#tPool+1] = r.CivilizationType
  end
end
print("  池子里的城邦文明总数 = " .. #tPool)

-- ── 2. 扫描全部玩家槽位（0~63），记录每个槽位的文明 ─────────────────────
local tSlot = {}          -- civType -> {slots...}
local nSlot = 0
for i = 0, 63 do
  local pc = nil
  pcall(function() pc = PlayerConfigurations[i] end)
  if pc ~= nil then
    local civ = nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    if civ ~= nil and civ ~= "" then
      nSlot = nSlot + 1
      tSlot[civ] = tSlot[civ] or {}
      table.insert(tSlot[civ], i)
    end
  end
end
print("  有文明名的槽位数 = " .. nSlot)

-- ── 3. ★ 池子里有、但【没有任何槽位】的城邦 ─────────────────────────────
print("")
print("=== ★ 池子里有、但【无槽位】的城邦 ===")
local tNoSlot = {}
for _, civ in ipairs(tPool) do
  if tSlot[civ] == nil then
    tNoSlot[#tNoSlot+1] = civ
  end
end
if #tNoSlot == 0 then
  print("  （无）→ 池子里每个城邦都至少有一个槽位")
else
  for _, civ in ipairs(tNoSlot) do print("    " .. civ) end
end
print("  → 共 " .. #tNoSlot .. " 个")

-- ── 4. 池子里的城邦，各自的槽位情况（前 12 个举例）─────────────────────
print("")
print("=== 池子城邦的槽位分布（举例 12 个）===")
local n = 0
for _, civ in ipairs(tPool) do
  local sl = tSlot[civ]
  if sl ~= nil then
    local alive = nil
    pcall(function() alive = Players[sl[1]]:IsAlive() end)
    print(string.format("    %-30s 槽位=%s alive=%s", civ, tostring(sl[1]), tostring(alive)))
    n = n + 1
    if n >= 12 then break end
  end
end

-- ── 5. 有没有【完全空的槽位】（无文明名）──────────────────────────────
print("")
print("=== 完全空的槽位（无文明名）===")
local tEmpty = {}
for i = 0, 63 do
  local pc = nil
  pcall(function() pc = PlayerConfigurations[i] end)
  if pc ~= nil then
    local civ = nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    if civ == nil or civ == "" then tEmpty[#tEmpty+1] = i end
  end
end
print("  空槽位: " .. (#tEmpty > 0 and table.concat(tEmpty, ", ") or "（无）"))
print("  → 共 " .. #tEmpty .. " 个")

-- ── 6. GetMaxPlayers / 槽位上限 ─────────────────────────────────────────
print("")
print("=== 槽位上限 ===")
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm ~= nil then
  local ok, v = pcall(function() return pm:GetMaxPlayers() end)
  print("  PlayerManager:GetMaxPlayers() = " .. tostring(ok and v or "ERR"))
end
print("=== 结束 ===")
