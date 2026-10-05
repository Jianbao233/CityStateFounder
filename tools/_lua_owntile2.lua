-- ===========================================================================
-- 复现用户场景：使节站在【自己领土】上建邦
--   第 1 回合玩家没领土 → 先给玩家建一座城（产生领土）→ 再测
-- ===========================================================================
print("=== 复现：自己领土上建邦 ===")

local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
print("  本地玩家 = " .. tostring(iMe))

-- ① 找一块无人、非水、非山的格给玩家建城
local cx, cy = -1, -1
pcall(function()
    local w, h = Map.GetGridSize()
    for y = 6, h-7 do
        for x = 6, w-7 do
            local pl = Map.GetPlot(x, y)
            if pl ~= nil then
                local own, w2, m2 = nil, nil, nil
                pcall(function() own = pl:GetOwner() end)
                pcall(function() w2 = pl:IsWater() end)
                pcall(function() m2 = pl:IsMountain() end)
                if own == -1 and w2 == false and m2 == false then
                    -- 半径 2 内无单位
                    local busy = false
                    for _, pid in ipairs(PlayerManager.GetAliveMajorIDs()) do
                        local p = Players[pid]
                        if p ~= nil then
                            pcall(function()
                                for _, u in p:GetUnits():Members() do
                                    local ux, uy = nil, nil
                                    pcall(function() ux = u:GetX() end); pcall(function() uy = u:GetY() end)
                                    if ux ~= nil and math.abs(ux-x) <= 2 and math.abs(uy-y) <= 2 then busy = true end
                                end
                            end)
                        end
                    end
                    if not busy then cx, cy = x, y; return end
                end
            end
        end
    end
end)
print("  给玩家建城的位置 = (" .. tostring(cx) .. "," .. tostring(cy) .. ")")
if cx < 0 then print("  ❌ 找不到"); return end

-- ② 给玩家建城
local ok1 = pcall(function() Players[iMe]:GetCities():Create(cx, cy) end)
local nCity = 0; pcall(function() nCity = Players[iMe]:GetCities():GetCount() end)
print("  玩家建城 ok=" .. tostring(ok1) .. " 城市数=" .. tostring(nCity))

-- ③ 找一块【自己领土】的格
local tx, ty = -1, -1
pcall(function()
    local w, h = Map.GetGridSize()
    for y = 2, h-3 do
        for x = 2, w-3 do
            local pl = Map.GetPlot(x, y)
            if pl ~= nil then
                local own, w2, m2 = nil, nil, nil
                pcall(function() own = pl:GetOwner() end)
                pcall(function() w2 = pl:IsWater() end)
                pcall(function() m2 = pl:IsMountain() end)
                if own == iMe and w2 == false and m2 == false and not (x == cx and y == cy) then
                    tx, ty = x, y; return
                end
            end
        end
    end
end)
print("  自己领土格 = (" .. tostring(tx) .. "," .. tostring(ty) .. ")")
if tx < 0 then print("  ❌ 建城后仍无领土"); return end

-- ④ 把使节放到自己领土上
local ok2 = pcall(function() return UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", tx, ty) end)
print("  放使节到自己领土 ok=" .. tostring(ok2))

-- ⑤ 走面板的真实路径建邦（坐标 = 使节所在格 = 自己的领土）
local t = nil; pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" then
    for _, e in ipairs(t) do
        if e.Mode == "slot" or e.Mode == "reuse" then sCiv = e.Civ; break end
    end
end
print("  选中 = " .. tostring(sCiv))
if sCiv ~= nil then
    local ok3, r3 = pcall(ExposedMembers.CSF.RequestFound, sCiv, tx, ty, nil, iMe)
    print("  RequestFound ok=" .. tostring(ok3) .. " 返回=" .. tostring(r3))
end

for _ = 1, 400000 do end

-- ⑥ 复查
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
print("  实际槽位 = " .. tostring(iSlot))
if iSlot ~= nil then
    local cn = 0; pcall(function() cn = Players[iSlot]:GetCities():GetCount() end)
    print("  该城邦城市数 = " .. tostring(cn))
end
print("=== 完成 ===")
