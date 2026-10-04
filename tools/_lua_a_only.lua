-- ===========================================================================
-- (a) 单独验收：激活一个【没出现过】的城邦 → 推进回合 → 看是否建城
-- ★ 刻意不碰 (b)，一次只验一个变量（上次归因过快的教训）
-- ===========================================================================
print("=== (a) 单独验收 ===")

local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("  %-26s %s", l, ok and tostring(v) or "ERR"))
    return ok and v or nil
end

-- 找出【场上还没有】的城邦文明
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

local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" then
    for _, e in ipairs(t) do
        local c = e.Civ or e.CivilizationType
        if c ~= nil and tInPlay[c] ~= true then sCiv = c; break end
    end
end
print("  选中【场上还没有的】文明 = " .. tostring(sCiv))
if sCiv == nil then print("  ❌ 找不到（可能全都在场上了）"); return end

-- 找一块模组认可、且远离地图边缘的地
local fValid = ExposedMembers.CSF.IsValidLocation
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
local iX, iY = -1, -1
pcall(function()
    for y = 10, h - 11 do
        for x = 10, w - 11 do
            local plot = Map.GetPlot(x, y)
            if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
               and plot:GetFeatureType() == -1 and plot:IsMountain() == false then
                local land = 0
                for d = 0, 5 do
                    local nb = Map:GetAdjacentPlot(x, y, d)
                    if nb ~= nil and nb:IsWater() == false then land = land + 1 end
                end
                if land >= 4 then
                    local okv, bv = pcall(fValid, x, y, nil)
                    if okv and bv == true then iX, iY = x, y; return end
                end
            end
        end
    end
end)
print("  目标格 (" .. tostring(iX) .. "," .. tostring(iY) .. ")  ← 远离边缘（>=10）")
if iX < 0 then print("  ❌ 找不到地"); return end

-- ★ 调模组函数（应走【非副本】路径，因为该文明不在场上）
print("")
print("  ── 调用 FoundCityStateByCiv ──")
local ok, a, b, c, d = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCiv, iX, iY, nil, nil)
print("  调用 ok=" .. tostring(ok) .. " 返回=" .. tostring(a) .. ", " .. tostring(b)
      .. ", " .. tostring(c) .. ", " .. tostring(d))

-- 记录该城邦的槽位，供回合后复查
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
print("  ── 该城邦槽位 = " .. tostring(iSlot) .. " ──")
if iSlot ~= nil then
    chk("IsAlive", function() return Players[iSlot]:IsAlive() end)
    chk("SlotStatus", function() return PlayerConfigurations[iSlot]:GetSlotStatus() end)
    chk("GetCities:GetCount", function() return Players[iSlot]:GetCities():GetCount() end)
    chk("单位数", function()
        local n = 0
        for _ in Players[iSlot]:GetUnits():Members() do n = n + 1 end
        return n
    end)
    -- 记到 Game 属性里，回合后另一个脚本能读到
    pcall(function() Game:SetProperty("CSF_TestSlot", iSlot) end)
    pcall(function() Game:SetProperty("CSF_TestCiv", sCiv) end)
    pcall(function() Game:SetProperty("CSF_TestX", iX) end)
    pcall(function() Game:SetProperty("CSF_TestY", iY) end)
    print("  已记录测试槽位到 Game 属性（CSF_TestSlot=" .. tostring(iSlot) .. "）")
end
print("")
print("★ 下一步：跑 endturn 探针推进回合，再跑复查脚本")
print("=== 结束 ===")
