-- ===========================================================================
-- (a) 回合后复查：城邦建城了吗？崩了吗？
-- ===========================================================================
print("=== 回合后复查 ===")

local iSlot, sCiv = nil, nil
pcall(function() iSlot = Game:GetProperty("CSF_TestSlot") end)
pcall(function() sCiv = Game:GetProperty("CSF_TestCiv") end)
local iX, iY = nil, nil
pcall(function() iX = Game:GetProperty("CSF_TestX") end)
pcall(function() iY = Game:GetProperty("CSF_TestY") end)
print("  测试槽位 = " .. tostring(iSlot) .. "  文明 = " .. tostring(sCiv)
      .. "  目标格 = (" .. tostring(iX) .. "," .. tostring(iY) .. ")")

local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("  %-26s %s", l, ok and tostring(v) or "ERR"))
    return ok and v or nil
end

if iSlot ~= nil then
    print("")
    print("  ── 目标城邦 ──")
    chk("IsAlive", function() return Players[iSlot]:IsAlive() end)
    chk("SlotStatus", function() return PlayerConfigurations[iSlot]:GetSlotStatus() end)
    chk("GetCivType", function() return PlayerConfigurations[iSlot]:GetCivilizationTypeName() end)
    local nCity = chk("GetCities:GetCount", function() return Players[iSlot]:GetCities():GetCount() end)
    chk("单位数", function()
        local n = 0
        for _ in Players[iSlot]:GetUnits():Members() do n = n + 1 end
        return n
    end)
    if nCity ~= nil and nCity > 0 then
        pcall(function()
            for k = 0, nCity - 1 do
                local c = Players[iSlot]:GetCities():GetCityByIndex(k)
                if c ~= nil then
                    print(string.format("    ★★ 城市: %s @ (%d,%d)  人口 %d",
                          tostring(c:GetName()), c:GetX(), c:GetY(), c:GetPopulation()))
                end
            end
        end)
    end
end

print("")
print("  ── 全局城邦 ──")
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
            local civ, cn, sf = nil, 0, nil
            pcall(function() civ = pc:GetCivilizationTypeName() end)
            pcall(function() cn = pl:GetCities():GetCount() end)
            pcall(function() sf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
            n = n + 1
            nCity = nCity + cn
            print(string.format("    slot %2d cities=%d 后缀=%-5s %s", j, cn, tostring(sf), tostring(civ)))
        end
    end
end
print("    存活城邦 " .. n .. " 个，城市总数 " .. nCity)
local t = nil
pcall(function() t = Game.GetCurrentGameTurn() end)
print("    当前回合 = " .. tostring(t))
print("=== 结束 ===")
