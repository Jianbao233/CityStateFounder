-- ===========================================================================
-- CSF 模组函数验收：(a) 建邦 → (b) 副本
-- 走【模组自己的导出函数】，不是我的探针 —— 验证真正交付给玩家的路径
-- ===========================================================================
print("=== (a)(b) 走模组自己的函数 ===")
print("  ApplyCityStateColor = " .. type(ExposedMembers.CSF.ApplyCityStateColor))
print("  ActivateCityState   = " .. type(ExposedMembers.CSF.ActivateCityState))
print("  FoundCityStateByCiv = " .. type(ExposedMembers.CSF.FoundCityStateByCiv))
print("  C6FW.ActivatePlayer = " .. type(C6FW ~= nil and C6FW.ActivatePlayer or nil))

-- 找一块模组认可的地
local fValid = ExposedMembers.CSF.IsValidLocation
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
local function findPlot()
    local iX, iY = -1, -1
    pcall(function()
        for y = 8, h - 9 do
            for x = 8, w - 9 do
                local plot = Map.GetPlot(x, y)
                if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
                   and plot:GetFeatureType() == -1 and plot:IsMountain() == false then
                    local land = 0
                    for d = 0, 5 do
                        local nb = Map.GetAdjacentPlot(x, y, d)
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
    return iX, iY
end

-- 统计存活城邦
local function report(tag)
    print("  ── " .. tag .. " ──")
    local n = 0
    for j = 0, 63 do
        local pc, pl = nil, nil
        pcall(function() pc = PlayerConfigurations[j] end)
        pcall(function() pl = Players[j] end)
        if pc ~= nil and pl ~= nil then
            local lvl, alive = nil, nil
            pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
            pcall(function() alive = pl:IsAlive() end)
            if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then
                local civ, cn, sf, uni = nil, 0, nil, 0
                pcall(function() civ = pc:GetCivilizationTypeName() end)
                pcall(function() cn = pl:GetCities():GetCount() end)
                pcall(function() sf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
                pcall(function() for _ in pl:GetUnits():Members() do uni = uni + 1 end end)
                n = n + 1
                print(string.format("    slot %2d cities=%d 单位=%d 后缀=%-5s %s",
                      j, cn, uni, tostring(sf), tostring(civ)))
            end
        end
    end
    print("    存活城邦共 " .. n .. " 个")
    return n
end

report("起点")

-- ---------------------------------------------------------------------------
print("")
print("=== (a) 建一个城邦（用模组函数）===")
local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" and #t > 0 then sCiv = t[1].Civ or t[1].CivilizationType end
print("  目标文明 = " .. tostring(sCiv))
if sCiv ~= nil then
    local x, y = findPlot()
    print("  目标格 (" .. tostring(x) .. "," .. tostring(y) .. ")")
    if x > 0 then
        local ok, a, b, c = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCiv, x, y, nil, nil)
        print("  调用 ok=" .. tostring(ok) .. " 返回=" .. tostring(a) .. ", " .. tostring(b)
              .. ", " .. tostring(c))
    end
end
report("(a) 之后")

-- ---------------------------------------------------------------------------
print("")
print("=== (b) 造一个副本（同一个文明再来一次）===")
if sCiv ~= nil then
    local x2, y2 = findPlot()
    print("  目标格 (" .. tostring(x2) .. "," .. tostring(y2) .. ")")
    if x2 > 0 then
        local ok2, a2, b2, c2 = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCiv, x2, y2, nil, nil)
        print("  调用 ok=" .. tostring(ok2) .. " 返回=" .. tostring(a2) .. ", " .. tostring(b2)
              .. ", " .. tostring(c2))
    end
end
report("(b) 之后")

print("")
print("★★★ 请点下一回合：验证 (a) 和 (b) 的城邦是否建城、是否崩溃")
print("=== 结束 ===")
