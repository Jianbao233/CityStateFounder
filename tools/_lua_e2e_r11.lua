-- ===========================================================================
-- 端到端验收：走面板真实路径（RequestFound）建一个 slot 模式的城邦
-- ===========================================================================
print("=== 端到端验收 ===")

local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
if type(t) ~= "table" then print("  ❌ 拿不到列表"); return end

-- 挑一个 Mode == "slot" 的（新路径）
local sCiv, iSlotHint = nil, nil
for _, e in ipairs(t) do
    if e.Mode == "slot" then
        sCiv, iSlotHint = e.Civ, e.ReusePlayerID
        break
    end
end
print("  选中 = " .. tostring(sCiv) .. "（预期槽 " .. tostring(iSlotHint) .. "，Mode=slot）")
if sCiv == nil then print("  ❌ 没有 slot 模式的"); return end

-- 找地
local x, y = -1, -1
local okF, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if okF then x, y = a, b end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x < 0 then print("  ❌ 找不到地"); return end

-- 走面板的真实路径
local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
local ok, r1 = pcall(ExposedMembers.CSF.RequestFound, sCiv, x, y, nil, iMe)
print("  RequestFound ok=" .. tostring(ok) .. " 返回=" .. tostring(r1))

-- 复查
local iSlot = nil
for j = 0, 63 do
    local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
    if pc ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = Players[j]:IsAlive() end)
        if civ == sCiv and alive == true then iSlot = j; break end
    end
end
print("")
print("  实际槽位 = " .. tostring(iSlot))
if iSlot ~= nil then
    local function try(f) local o,v = pcall(f); return o and tostring(v) or "ERR" end
    local pl = Players[iSlot]
    local pc = PlayerConfigurations[iSlot]
    print("    IsAlive      = " .. try(function() return pl:IsAlive() end))
    print("    GetCivType   = " .. try(function() return pc:GetCivilizationTypeName() end))
    print("    GetSlotStatus= " .. try(function() return pc:GetSlotStatus() end))
    print("    GetDiplomacy = " .. try(function() return pl:GetDiplomacy() end))
    print("    GetInfluence = " .. try(function() return pl:GetInfluence() end))
    print("    GetCities    = " .. try(function() return pl:GetCities():GetCount() end))
    print("    单位数       = " .. try(function() local n=0; for _ in pl:GetUnits():Members() do n=n+1 end; return n end))
end
print("")
print("=== 端到端验收执行完毕 ===")
