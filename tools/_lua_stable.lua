-- ===========================================================================
-- 稳定路径验证：复用【同文明】的休眠槽（不改文明 → 不崩）
-- ===========================================================================
print("=== 稳定路径验证 ===")

local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("  %-26s %s", l, ok and tostring(v) or "ERR"))
    return ok and v or nil
end

-- ① 先列出所有休眠城邦（0 城 = 还没建城）
print("  取休眠城邦列表...")
local t = nil
local ok, r = pcall(ExposedMembers.CSF.GetDormantCityStates)
print("    GetDormantCityStates ok=" .. tostring(ok) .. " 类型=" .. type(r))
t = r
if type(t) ~= "table" or #t == 0 then
    print("  ❌ 没有休眠城邦可用")
    return
end
print("  休眠城邦 " .. #t .. " 个:")
local tCiv = {}
for i, e in ipairs(t) do
    local c = nil
    if type(e) == "table" then c = e.Civ or e.CivilizationType else c = tostring(e) end
    tCiv[#tCiv + 1] = c
    if i <= 10 then print("    [" .. i .. "] " .. tostring(c)) end
end

-- ② 挑一个【场上没有的】休眠城邦（它本来就不在场上 = 满足 (a)）
local tAlive = {}
for j = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[j] end)
    pcall(function() pl = Players[j] end)
    if pc ~= nil and pl ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        if civ ~= nil and alive == true then tAlive[civ] = true end
    end
end
local sTarget = nil
for _, c in ipairs(tCiv) do
    if c ~= nil and tAlive[c] ~= true then sTarget = c; break end
end
if sTarget == nil then
    print("  ⚠️ 所有休眠城邦都已在场上，改用第一个")
    sTarget = tCiv[1]
end
print("")
print("  目标（场上没有的休眠城邦）= " .. tostring(sTarget))

-- ③ 找地（新查找器会避开有单位的格）
local x, y, why = -1, -1, nil
local ok2, a, b, c = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if ok2 then x, y, why = a, b, c end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")  " .. tostring(why))
if x < 0 then print("  ❌ 找不到地"); return end

-- ④ 调用（应走【复用】分支，不改文明）
print("")
print("  ── 调用 FoundCityStateByCiv ──")
local ok3, r1, r2, r3 = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sTarget, x, y, nil, nil)
print("  ok=" .. tostring(ok3) .. " 返回=" .. tostring(r1) .. ", " .. tostring(r2) .. ", " .. tostring(r3))

-- ⑤ 复查该城邦
local iSlot = nil
for j = 0, 63 do
    local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = Players[j]:IsAlive() end)
        if civ == sTarget and alive == true then iSlot = j; break end
    end
end
print("")
print("  槽位 = " .. tostring(iSlot))
if iSlot ~= nil then
    chk("IsAlive", function() return Players[iSlot]:IsAlive() end)
    chk("SlotStatus", function() return PlayerConfigurations[iSlot]:GetSlotStatus() end)
    chk("GetCivType", function() return PlayerConfigurations[iSlot]:GetCivilizationTypeName() end)
    chk("GetCivLevel", function() return PlayerConfigurations[iSlot]:GetCivilizationLevelTypeName() end)
    chk("GetCities", function() return Players[iSlot]:GetCities():GetCount() end)
    chk("单位数", function() local n = 0; for _ in Players[iSlot]:GetUnits():Members() do n = n + 1 end; return n end)
    chk("GetDiplomacy", function() return Players[iSlot]:GetDiplomacy() end)
    chk("GetInfluence", function() return Players[iSlot]:GetInfluence() end)
end

print("")
print("=== 全场城邦总览 ===")
local n, nCity = 0, 0
for j = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[j] end)
    pcall(function() pl = Players[j] end)
    if pc ~= nil and pl ~= nil then
        local lvl, alive = nil, nil
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then
            local civ, cn, uni = nil, 0, 0
            pcall(function() civ = pc:GetCivilizationTypeName() end)
            pcall(function() cn = pl:GetCities():GetCount() end)
            pcall(function() for _ in pl:GetUnits():Members() do uni = uni + 1 end end)
            n = n + 1; nCity = nCity + cn
            print(string.format("  slot %2d  城市=%d  单位=%d  %s", j, cn, uni, tostring(civ)))
        end
    end
end
print("  存活城邦 " .. n .. " 个，城市总数 " .. nCity)
print("")
print("★ 请点下一回合：看是否建城、是否崩溃")
print("=== 结束 ===")
