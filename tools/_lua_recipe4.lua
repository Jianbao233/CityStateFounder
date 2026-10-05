-- ===========================================================================
-- 四步配方测试：激活一个未激活的城邦槽，然后让引擎自己驱动它建城
--
-- ① C6FW.ActivatePlayer(slot)        -- DLL
-- ② pm:SetPlayerSlotStatus(slot, 1)  -- ★ 关键
-- ③ C6FW.SetAlive(slot, 1)
-- ④ 放移民（UNIT_SETTLER）
--
-- ⚠️ 绝不再调 UnitManager.CanStartOperation / RequestOperation
--    （跨玩家调用会原生崩溃，地址 0xcc）
-- ===========================================================================
print("=== 四步配方测试 ===")

local function try(f)
    local ok, v = pcall(f)
    if not ok then return "ERR(" .. tostring(v):sub(1,50) .. ")" end
    return tostring(v)
end

-- 找第一个未激活的城邦槽
local iT, sCiv = nil, nil
for j = 0, 63 do
    local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local civ, lvl = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and civ ~= nil and civ ~= "" then
            local alive = nil; pcall(function() alive = Players[j]:IsAlive() end)
            if alive ~= true then iT, sCiv = j, civ; break end
        end
    end
end
print("  目标槽 = " .. tostring(iT) .. "  文明 = " .. tostring(sCiv))
if iT == nil then print("  ❌ 没有未激活的城邦槽"); return end

-- ① DLL 激活
local ok1, r1 = pcall(C6FW.ActivatePlayer, iT)
print("  ① ActivatePlayer  ok=" .. tostring(ok1) .. " 返回=" .. tostring(r1))

-- ② 槽位状态 → 1
local pm = nil; pcall(function() pm = WorldBuilder.PlayerManager() end)
local ok2, r2 = pcall(function() return pm:SetPlayerSlotStatus(iT, 1) end)
print("  ② SetSlotStatus   ok=" .. tostring(ok2) .. " 返回=" .. tostring(r2))
local st = nil; pcall(function() st = PlayerConfigurations[iT]:GetSlotStatus() end)
print("     现在的 status = " .. tostring(st))

-- ③ SetAlive
local ok3, r3 = pcall(C6FW.SetAlive, iT, 1)
print("  ③ SetAlive        ok=" .. tostring(ok3) .. " 返回=" .. tostring(r3))

-- ④ 放移民
local x, y = -1, -1
local okF, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if okF then x, y = a, b end
print("  ④ 找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x > 0 then
    local ok4, r4 = pcall(function() return UnitManager.InitUnit(iT, "UNIT_SETTLER", x, y) end)
    print("     放移民 ok=" .. tostring(ok4) .. " 返回=" .. tostring(r4))
end

-- 复查
print("")
print("  ── 复查 slot " .. iT .. " ──")
local pl = nil; pcall(function() pl = Players[iT] end)
local pc = nil; pcall(function() pc = PlayerConfigurations[iT] end)
print("    IsAlive      = " .. try(function() return pl:IsAlive() end))
print("    GetCivType   = " .. try(function() return pc:GetCivilizationTypeName() end))
print("    GetSlotStatus= " .. try(function() return pc:GetSlotStatus() end))
print("    GetCities    = " .. try(function() return pl:GetCities():GetCount() end))
print("    GetDiplomacy = " .. try(function() return pl:GetDiplomacy() end))
print("    GetInfluence = " .. try(function() return pl:GetInfluence() end))
print("    单位数       = " .. try(function() local n=0; for _ in pl:GetUnits():Members() do n=n+1 end; return n end))
print("")
print("=== 四步配方执行完毕 ===")
