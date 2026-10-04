-- ===========================================================================
-- CSF_DLL_验收.lua —— DLL 路线完整验收（(a) + (b)）
-- ===========================================================================
-- 用法：在 GameCore_Tuner 上下文里跑
--   (a) 激活一个【地图生成时没出现过】的城邦
--   (b) 复制一个【场上已存在】的城邦（能力+颜色复用，只有名字/ID 不同）
--
-- 前置：C6FW 已部署（含 ActivatePlayer / SetAlive / SetPlayerColor）
--
-- ── 为什么要 DLL（Lua 做不到的原因）──────────────────────────────────────
--   Lua 的 InitializePlayer 走 FUN_180617370 那道门，对槽位状态 5 直接 return，
--   **从不调用真正的激活函数 FUN_1802f9350**（它初始化玩家的 16 个子系统）。
--   结果：玩家对象"半成品" → 点下一回合 AI 处理时原生崩溃。
--
--   DLL 的 ActivatePlayer 补上的正是这一步。
-- ===========================================================================

local function say(s) print(s) end
local function chk(label, fn)
    local ok, v = pcall(fn)
    say(string.format("    %-30s %s", label, ok and tostring(v) or ("ERR")))
    return ok and v or nil
end

-- 找一块模组认可的空地
local function findPlot()
    local fValid = ExposedMembers.CSF.IsValidLocation
    if fValid == nil then return -1, -1 end
    local w, h = 0, 0
    pcall(function() w, h = Map.GetGridSize() end)
    local iX, iY = -1, -1
    pcall(function()
        for y = 4, h - 5 do
            for x = 4, w - 5 do
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

-- 找一个【预注册但没上场】的城邦槽（槽位状态 5、alive=false）
local function findDormantSlot()
    for i = 0, 63 do
        local pc, pl = nil, nil
        pcall(function() pc = PlayerConfigurations[i] end)
        pcall(function() pl = Players[i] end)
        if pc ~= nil and pl ~= nil then
            local civ, alive, st = nil, nil, nil
            pcall(function() civ = pc:GetCivilizationTypeName() end)
            pcall(function() alive = pl:IsAlive() end)
            pcall(function() st = pc:GetSlotStatus() end)
            if civ ~= nil and civ ~= "" and alive == false and st == 5 then
                local bCS = false
                pcall(function()
                    for r in GameInfo.Civilizations() do
                        if r.CivilizationType == civ
                           and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
                            bCS = true; break
                        end
                    end
                end)
                if bCS then return i, civ end
            end
        end
    end
    return -1, nil
end

-- ★ 完整激活：Lua 配置 + DLL 激活
local function activateFully(slot)
    local pm = nil
    pcall(function() pm = WorldBuilder.PlayerManager() end)
    say("  ── 完整激活 slot " .. tostring(slot) .. " ──")

    -- ① DLL 激活（创建游戏侧玩家对象 + 16 子系统）
    local ok1, r1 = pcall(C6FW.ActivatePlayer, slot)
    say(string.format("    ActivatePlayer              ok=%s 返回=%s", tostring(ok1), tostring(r1)))
    chk("HasGamePlayer", function() return C6FW.HasGamePlayer(slot) end)

    -- ② 槽位状态 → 1（Lua 的 API 本来就能用）
    if pm ~= nil then
        local ok2, r2 = pcall(function() return pm:SetPlayerSlotStatus(slot, 1) end)
        say(string.format("    SetPlayerSlotStatus(1)      ok=%s 返回=%s", tostring(ok2), tostring(r2)))
    end

    -- ③ IsAlive 置位（DLL 直接写 player+0x258）
    local ok3, r3 = pcall(C6FW.SetAlive, slot, 1)
    say(string.format("    SetAlive(1)                 ok=%s 返回=%s", tostring(ok3), tostring(r3)))
    chk("C6FW.GetAlive", function() return C6FW.GetAlive(slot) end)
    chk("Players:IsAlive", function() return Players[slot]:IsAlive() end)

    -- ④ 复查
    chk("SlotStatus", function() return PlayerConfigurations[slot]:GetSlotStatus() end)
    chk("GetCivLevel", function() return PlayerConfigurations[slot]:GetCivilizationLevelTypeName() end)
    chk("GetCities:GetCount", function() return Players[slot]:GetCities():GetCount() end)
    chk("GetDiplomacy", function() return Players[slot]:GetDiplomacy() end)
    chk("GetInfluence", function() return Players[slot]:GetInfluence() end)
    chk("GetTreasury", function() return Players[slot]:GetTreasury() end)
    chk("GetColor", function() return PlayerConfigurations[slot]:GetColor() end)
    return true
end

-- ===========================================================================
say("==============================================================")
say("=== CSF DLL 路线验收 ===")
say("==============================================================")
say("  C6FW = " .. type(C6FW))
if C6FW == nil then say("  ❌ C6FW 不可用（未部署？）"); return end
for _, k in ipairs({ "ActivatePlayer", "SetAlive", "GetAlive", "SetPlayerColor", "HasGamePlayer" }) do
    say(string.format("  C6FW.%-16s = %s", k, type(C6FW[k])))
end

-- ---------------------------------------------------------------------------
say("")
say("==============================================================")
say("=== (a) 激活一个【地图生成时没出现过】的城邦 ===")
say("==============================================================")
local iA, sCivA = findDormantSlot()
say("  目标: slot " .. tostring(iA) .. "  " .. tostring(sCivA))
if iA >= 0 then
    activateFully(iA)
    local x, y = findPlot()
    say("  目标格 (" .. tostring(x) .. "," .. tostring(y) .. ")")
    if x > 0 then
        local okU = pcall(function() UnitManager.InitUnit(iA, "UNIT_SETTLER", x, y) end)
        say("  放移民 ok=" .. tostring(okU))
        say(string.format("  ★ 请点下一回合：看 (%d,%d) 是否建城且不崩", x, y))
    end
else
    say("  ⚠️ 本局没有可激活的休眠槽（城邦数可能已拉满）")
end

-- ---------------------------------------------------------------------------
say("")
say("==============================================================")
say("=== (b) 复制一个【场上已存在】的城邦 ===")
say("==============================================================")
-- 找一个已经上场的城邦
local iSrc, sCivB, sLdrB = -1, nil, nil
for i = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[i] end)
    pcall(function() pl = Players[i] end)
    if pc ~= nil and pl ~= nil then
        local civ, alive, lvl = nil, nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        if civ ~= nil and alive == true and lvl == "CIVILIZATION_LEVEL_CITY_STATE" then
            pcall(function() sLdrB = pc:GetLeaderTypeName() end)
            iSrc, sCivB = i, civ
            break
        end
    end
end
say("  源城邦: slot " .. tostring(iSrc) .. "  " .. tostring(sCivB) .. "  领袖=" .. tostring(sLdrB))
if iSrc < 0 then
    say("  ⚠️ 场上还没有城邦，(b) 需要先有一个")
else
    local colSrc = nil
    pcall(function() colSrc = C6FW.GetPlayerColor(PlayerConfigurations[iSrc]) end)
    say("  源颜色 = " .. tostring(colSrc))

    local iB, _ = findDormantSlot()
    say("  复制的目标槽 = " .. tostring(iB))
    if iB >= 0 then
        local pm = nil
        pcall(function() pm = WorldBuilder.PlayerManager() end)
        -- ① 释放 + 拿回
        pcall(function() pm:UninitializePlayer(iB) end)
        local iNew = nil
        pcall(function() iNew = pm:AddPlayer(true) end)
        say("  AddPlayer -> " .. tostring(iNew))
        if iNew ~= nil and iNew ~= -1 then
            -- ② 复用能力：把源城邦的文明/领袖设过来
            local okL = pcall(function()
                pm:SetPlayerLeader(iNew, sLdrB, sCivB, "CIVILIZATION_LEVEL_CITY_STATE")
            end)
            say("  SetPlayerLeader（复用文明/领袖） ok=" .. tostring(okL))
            pcall(function() pm:SetRandomMinorStartingPosition(iNew) end)
            -- ③ ★ DLL 激活（缺了这步就会崩）
            activateFully(iNew)
            -- ④ 复用颜色
            if colSrc ~= nil then
                local okC = pcall(function()
                    C6FW.SetPlayerColor(PlayerConfigurations[iNew], colSrc)
                end)
                say("  SetPlayerColor（复用源颜色） ok=" .. tostring(okC))
                chk("新槽 GetColor", function() return C6FW.GetPlayerColor(PlayerConfigurations[iNew]) end)
            end
            -- ⑤ 放移民
            local x2, y2 = findPlot()
            say("  目标格 (" .. tostring(x2) .. "," .. tostring(y2) .. ")")
            if x2 > 0 then
                local okU2 = pcall(function() UnitManager.InitUnit(iNew, "UNIT_SETTLER", x2, y2) end)
                say("  放移民 ok=" .. tostring(okU2))
                say(string.format("  ★ 请点下一回合：看 (%d,%d) 是否建城且不崩，名字应为「%s II」",
                    x2, y2, tostring(sCivB)))
            end
        end
    end
end

say("")
say("==============================================================")
say("=== 结束 —— 请点下一回合，然后回报：崩不崩 / 有没有城 / 名字 ===")
say("==============================================================")
