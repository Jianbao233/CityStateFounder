-- ===========================================================================
-- (a) 最终验收 v2：用模组的 FindFoundLocation 找地 → 建邦 → 记录槽位
-- ===========================================================================
print("=== (a) 最终验收 v2 ===")

local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("  %-26s %s", l, ok and tostring(v) or "ERR"))
    return ok and v or nil
end

-- 场上已有的文明
local tInPlay = {}
for j = 0, 63 do
    local pc = nil
    pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = Players[j]:IsAlive() end)
        if civ ~= nil and alive == true then tInPlay[civ] = true end
    end
end

-- 挑一个场上没有的城邦
local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" then
    for _, e in ipairs(t) do
        local c = e.Civ or e.CivilizationType
        if c ~= nil and tInPlay[c] ~= true then sCiv = c; break end
    end
end
print("  选中【场上没有的】文明 = " .. tostring(sCiv))
if sCiv == nil then print("  ❌ 找不到"); return end

-- ★ 用模组新的全地图查找器
print("  FindFoundLocation = " .. type(ExposedMembers.CSF.FindFoundLocation))
local iX, iY, sWhy = -1, -1, nil
if ExposedMembers.CSF.FindFoundLocation ~= nil then
    local ok, a, b, c = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
    if ok then iX, iY, sWhy = a, b, c end
end
print("  找到地块 (" .. tostring(iX) .. "," .. tostring(iY) .. ")  原因=" .. tostring(sWhy))
if iX < 0 then
    print("  ❌ 全地图都找不到地")
    return
end

-- 调用模组函数建邦
print("")
print("  ── 调用 FoundCityStateByCiv ──")
local ok, a, b, c, d = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCiv, iX, iY, nil, nil)
print("  调用 ok=" .. tostring(ok) .. " 返回=" .. tostring(a) .. ", " .. tostring(b)
      .. ", " .. tostring(c) .. ", " .. tostring(d))

-- 记录槽位
local iSlot = nil
for j = 0, 63 do
    local pc = nil
    pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = Players[j]:IsAlive() end)
        if civ == sCiv and alive == true then iSlot = j; break end
    end
end
print("")
print("  该城邦槽位 = " .. tostring(iSlot))
if iSlot ~= nil then
    chk("IsAlive", function() return Players[iSlot]:IsAlive() end)
    chk("SlotStatus", function() return PlayerConfigurations[iSlot]:GetSlotStatus() end)
    chk("GetCities:GetCount", function() return Players[iSlot]:GetCities():GetCount() end)
    chk("单位数", function()
        local n = 0
        for _ in Players[iSlot]:GetUnits():Members() do n = n + 1 end
        return n
    end)
    pcall(function() Game:SetProperty("CSF_TestSlot", iSlot) end)
    pcall(function() Game:SetProperty("CSF_TestCiv", sCiv) end)
    pcall(function() Game:SetProperty("CSF_TestX", iX) end)
    pcall(function() Game:SetProperty("CSF_TestY", iY) end)
    print("  已记录到 Game 属性（CSF_TestSlot=" .. tostring(iSlot) .. "）")
end
print("")
print("★ 下一步：切到 Main State 跑 DoEndTurn()，再回 GameCore 复查")
print("=== 结束 ===")
