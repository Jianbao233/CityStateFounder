-- ===========================================================================
-- (b) 副本测试：把一个【已在场上的城邦】复制到另一个槽
--
-- 之前这条路【必崩】（读 NULL+0xb0）。现在有了 DLL 修复（+0x83a + 子系统写回）
-- 和四步配方，重新测。
--
-- ⚠️ 不碰 UnitManager.CanStartOperation / RequestOperation（跨玩家调用会崩 0xcc）
-- ===========================================================================
print("=== (b) 副本测试 ===")

local function try(f)
    local ok, v = pcall(f)
    if not ok then return "ERR(" .. tostring(v):sub(1,50) .. ")" end
    return tostring(v)
end

-- ① 找一个【已在场上的】城邦当源
local iSrc, sSrcCiv, sSrcLeader = nil, nil, nil
for j = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[j] end)
    pcall(function() pl = Players[j] end)
    if pc ~= nil and pl ~= nil then
        local lvl, alive, civ = nil, nil, nil
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true and civ ~= nil then
            if not civ:find("CSF_CS_") then
                iSrc, sSrcCiv = j, civ
                pcall(function() sSrcLeader = pc:GetLeaderTypeName() end)
                break
            end
        end
    end
end
print("  源城邦: slot " .. tostring(iSrc) .. "  " .. tostring(sSrcCiv) .. "  领袖=" .. tostring(sSrcLeader))
if iSrc == nil then print("  ❌ 找不到源城邦"); return end

-- ② 找一个【未激活的】槽当目标
local iDst, sDstCiv = nil, nil
for j = 0, 63 do
    local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local lvl, civ = nil, nil
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and civ ~= nil and civ ~= "" then
            local alive = nil; pcall(function() alive = Players[j]:IsAlive() end)
            if alive ~= true then iDst, sDstCiv = j, civ; break end
        end
    end
end
print("  目标槽: slot " .. tostring(iDst) .. "  （原本 " .. tostring(sDstCiv) .. "）")
if iDst == nil then print("  ❌ 没有未激活的槽"); return end

-- ③ 把目标的文明/领袖改成源城邦的（★ 这一步以前必崩）
print("")
print("  ── ③ 改文明（把 " .. tostring(sSrcCiv) .. " 设到 slot " .. tostring(iDst) .. "）──")
local pm = nil; pcall(function() pm = WorldBuilder.PlayerManager() end)
local ok3, r3 = pcall(function()
    return pm:SetPlayerLeader(iDst, sSrcLeader, sSrcCiv, "CIVILIZATION_LEVEL_CITY_STATE")
end)
print("  SetPlayerLeader ok=" .. tostring(ok3) .. " 返回=" .. tostring(r3))
local sNow = nil; pcall(function() sNow = PlayerConfigurations[iDst]:GetCivilizationTypeName() end)
print("  现在 slot " .. iDst .. " 的文明 = " .. tostring(sNow))

-- ④ 四步配方
print("")
print("  ── ④ 四步配方 ──")
local ok1, r1 = pcall(C6FW.ActivatePlayer, iDst)
print("    ① ActivatePlayer ok=" .. tostring(ok1) .. " 返回=" .. tostring(r1))
local ok2, r2 = pcall(function() return pm:SetPlayerSlotStatus(iDst, 1) end)
print("    ② SetSlotStatus  ok=" .. tostring(ok2) .. " 返回=" .. tostring(r2))
local ok4, r4 = pcall(C6FW.SetAlive, iDst, 1)
print("    ③ SetAlive       ok=" .. tostring(ok4) .. " 返回=" .. tostring(r4))
local x, y = -1, -1
local okF, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if okF then x, y = a, b end
print("    ④ 找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x > 0 then
    local ok5, r5 = pcall(function() return UnitManager.InitUnit(iDst, "UNIT_SETTLER", x, y) end)
    print("       放移民 ok=" .. tostring(ok5) .. " 返回=" .. tostring(r5))
end

-- ⑤ 复查
print("")
print("  ── ⑤ 复查 slot " .. tostring(iDst) .. " ──")
local plD = nil; pcall(function() plD = Players[iDst] end)
local pcD = nil; pcall(function() pcD = PlayerConfigurations[iDst] end)
print("    IsAlive      = " .. try(function() return plD:IsAlive() end))
print("    GetCivType   = " .. try(function() return pcD:GetCivilizationTypeName() end))
print("    GetLeader    = " .. try(function() return pcD:GetLeaderTypeName() end))
print("    GetSlotStatus= " .. try(function() return pcD:GetSlotStatus() end))
print("    GetCities    = " .. try(function() return plD:GetCities():GetCount() end))
print("    GetDiplomacy = " .. try(function() return plD:GetDiplomacy() end))
print("    单位数       = " .. try(function() local n=0; for _ in plD:GetUnits():Members() do n=n+1 end; return n end))

-- ⑥ 两个槽的文明是否相同
print("")
print("  ── ⑥ 同文明双槽检查 ──")
for j = 0, 63 do
    local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = Players[j]:IsAlive() end)
        if civ == sSrcCiv and alive == true then
            print("    slot " .. j .. "  " .. tostring(civ) .. "  IsAlive=true")
        end
    end
end
print("")
print("=== (b) 测试执行完毕 ===")
