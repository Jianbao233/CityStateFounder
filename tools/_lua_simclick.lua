-- ===========================================================================
-- 模拟人工点击「建立城邦」按钮的完整流程
--
-- 人工流程：
--   ① 选中建邦使节单位
--   ② 点它面板里的「建立城邦」动作
--   ③ 动作回调 → LuaEvents.CSF_OpenPanel(x, y, unitID, ownerID)
--   ④ 面板打开 → 玩家选城邦 → 点「建立」
--   ⑤ 面板 → ExposedMembers.CSF.RequestFound(civ, x, y, unitID, ownerID)
--   ⑥ GameCore → CSF_ProcessPending → CSF_FoundCityStateByCiv → 激活槽 + 放移民
--
-- 本脚本模拟 ③~⑥（面板 UI 的点击我无法用 Lua 模拟，所以直接从 ③ 开始，
-- 后面全走真实路径）。
-- ===========================================================================
print("=== 模拟人工点击流程 ===")

local iMe = 0
pcall(function() iMe = Game.GetLocalPlayer() end)

-- ① 找建邦使节（如果没有就造一个，模拟"玩家造了使节"）
local pEnvoy, ux, uy, uID = nil, nil, nil, nil
pcall(function()
    for _, u in Players[iMe]:GetUnits():Members() do
        local ut = nil
        pcall(function() ut = GameInfo.Units[u:GetType()].UnitType end)
        if ut == "UNIT_CSF_ENVOY" then pEnvoy = u; break end
    end
end)
if pEnvoy == nil then
    print("  场上没有使节 → 造一个（模拟玩家生产）")
    local bx, by = -1, -1
    pcall(function()
        for _, u in Players[iMe]:GetUnits():Members() do
            local x, y = nil, nil
            pcall(function() x = u:GetX() end); pcall(function() y = u:GetY() end)
            if x ~= nil and x >= 0 then bx, by = x, y; break end
        end
    end)
    if bx < 0 then print("  ❌ 找不到玩家单位"); return end
    local tx, ty = bx, by
    pcall(function()
        for d = 0, 5 do
            local pl = Map.GetAdjacentPlot(bx, by, d)
            if pl ~= nil and pl:IsWater() == false and pl:IsMountain() == false then
                tx, ty = pl:GetX(), pl:GetY(); return
            end
        end
    end)
    local okU, rU = pcall(function() return UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", tx, ty) end)
    print("  造使节 ok=" .. tostring(okU))
    pcall(function()
        for _, u in Players[iMe]:GetUnits():Members() do
            local ut = nil
            pcall(function() ut = GameInfo.Units[u:GetType()].UnitType end)
            if ut == "UNIT_CSF_ENVOY" then pEnvoy = u; break end
        end
    end)
end
if pEnvoy == nil then print("  ❌ 没有使节"); return end
pcall(function() ux = pEnvoy:GetX() end)
pcall(function() uy = pEnvoy:GetY() end)
pcall(function() uID = pEnvoy:GetID() end)
print("  使节 @ (" .. tostring(ux) .. "," .. tostring(uy) .. ") id=" .. tostring(uID))

-- ② 模拟面板打开（人工点动作后会发生的事）
print("")
print("  ② 触发 LuaEvents.CSF_OpenPanel（模拟点了使节的动作）")
local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
if type(t) ~= "table" then print("  ❌ 拿不到城邦列表"); return end

-- ③ 选一个（模拟玩家在面板里选了第一个可用的）
local sCiv, iHint = nil, nil
for _, e in ipairs(t) do
    if e.Mode == "reuse" or e.Mode == "slot" then sCiv, iHint = e.Civ, e.ReusePlayerID; break end
end
print("  ③ 选中 = " .. tostring(sCiv) .. "（Mode=" .. tostring(iHint) .. "）")
if sCiv == nil then print("  ❌ 没有可选的"); return end

-- ④ 找地
local x, y = -1, -1
local okF, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if okF then x, y = a, b end
print("  ④ 找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x < 0 then print("  ❌ 找不到地"); return end

-- ⑤ 模拟点「建立」→ RequestFound（面板的真实调用）
print("")
print("  ⑤ RequestFound（模拟点「建立」按钮）")
local ok5, r5 = pcall(ExposedMembers.CSF.RequestFound, sCiv, x, y, uID, iMe)
print("     ok=" .. tostring(ok5) .. " 返回=" .. tostring(r5))

-- ⑥ 等 GameCore 处理
for _ = 1, 200000 do end

-- ⑦ 复查
print("")
print("  ⑦ 复查")
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
print("     实际槽位 = " .. tostring(iSlot))
if iSlot ~= nil then
    local pl = Players[iSlot]
    local pc = PlayerConfigurations[iSlot]
    local function try(f) local o,v = pcall(f); return o and tostring(v) or "ERR" end
    print("     IsAlive      = " .. try(function() return pl:IsAlive() end))
    print("     GetCivType   = " .. try(function() return pc:GetCivilizationTypeName() end))
    print("     GetSlotStatus= " .. try(function() return pc:GetSlotStatus() end))
    print("     GetDiplomacy = " .. try(function() return pl:GetDiplomacy() end))
    print("     GetCities    = " .. try(function() return pl:GetCities():GetCount() end))
    print("     单位数       = " .. try(function() local n=0; for _ in pl:GetUnits():Members() do n=n+1 end; return n end))
end
print("")
print("=== 模拟流程执行完毕 ===")