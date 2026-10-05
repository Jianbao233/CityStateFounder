-- ===========================================================================
-- 自测：(a) 建一个场上没有的城邦 → (b) 建它的副本
-- 走【模组自己的导出函数】= 玩家在游戏里点「建立城邦」时走的同一条路
-- ===========================================================================
print("==============================================================")
print("=== 城邦缔造者 自测 ===")
print("==============================================================")

local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("    %-26s %s", l, ok and tostring(v) or "ERR"))
    return ok and v or nil
end

-- C6FW 能力
print("  C6FW 能力:")
for _, k in ipairs({ "ActivatePlayer", "SetAlive", "GetAlive", "HasGamePlayer", "SetPlayerColor" }) do
    print(string.format("    %-20s %s", k, type(C6FW ~= nil and C6FW[k] or nil)))
end

-- 场上已有的文明
--   ⚠️ 只算【alive=true】的！把所有带文明的玩家都算进来会把 54 个城邦
--      全判成"在场"（预注册的槽也带文明）—— 这是我第一版的 bug。
local tInPlay = {}
local nCS = 0
for j = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[j] end)
    pcall(function() pl = Players[j] end)
    if pc ~= nil and pl ~= nil then
        local civ, alive, lvl = nil, nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        if civ ~= nil and civ ~= "" and alive == true then tInPlay[civ] = true end
        if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true then nCS = nCS + 1 end
    end
end
print("")
print("  场上存活城邦 = " .. nCS .. " 个")

-- 挑一个【场上没有的】城邦
local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" then
    for _, e in ipairs(t) do
        local c = e.Civ or e.CivilizationType
        if c ~= nil and tInPlay[c] ~= true then sCiv = c; break end
    end
end
print("  选中（场上没有的）= " .. tostring(sCiv))

-- ===========================================================================
print("")
print("==============================================================")
print("=== (a) 建一个场上没有的城邦 ===")
print("==============================================================")
local iA = -1
if sCiv == nil then
    print("  ❌ 找不到可用文明")
else
    local x, y, why = -1, -1, nil
    if ExposedMembers ~= nil and ExposedMembers.CSF ~= nil and ExposedMembers.CSF.FindFoundLocation ~= nil then
        local ok, a, b, c = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
        if ok then x, y, why = a, b, c end
    end
    print("  找地: (" .. tostring(x) .. "," .. tostring(y) .. ")  原因=" .. tostring(why))
    if x > 0 then
        local ok, a, b, c = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCiv, x, y, nil, nil)
        print("  FoundCityStateByCiv ok=" .. tostring(ok) .. " 返回=" .. tostring(a)
              .. "," .. tostring(b) .. "," .. tostring(c))
        for j = 0, 63 do
            local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
            if pc ~= nil then
                local civ, alive = nil, nil
                pcall(function() civ = pc:GetCivilizationTypeName() end)
                pcall(function() alive = Players[j]:IsAlive() end)
                if civ == sCiv and alive == true then iA = j; break end
            end
        end
    end
end
print("")
print("  (a) 结果槽位 = " .. tostring(iA))
if iA >= 0 then
    chk("IsAlive", function() return Players[iA]:IsAlive() end)
    chk("SlotStatus", function() return PlayerConfigurations[iA]:GetSlotStatus() end)
    chk("GetCivType", function() return PlayerConfigurations[iA]:GetCivilizationTypeName() end)
    chk("GetCivLevel", function() return PlayerConfigurations[iA]:GetCivilizationLevelTypeName() end)
    chk("IsMajor", function() return Players[iA]:IsMajor() end)
    chk("GetCities", function() return Players[iA]:GetCities():GetCount() end)
    chk("单位数", function() local n = 0; for _ in Players[iA]:GetUnits():Members() do n = n + 1 end; return n end)
    chk("GetDiplomacy", function() return Players[iA]:GetDiplomacy() end)
    chk("GetInfluence", function() return Players[iA]:GetInfluence() end)
    chk("GetTreasury", function() return Players[iA]:GetTreasury() end)
end

-- ===========================================================================
print("")
print("==============================================================")
print("=== (b) 建一个已存在城邦的副本 ===")
print("==============================================================")
-- 找一个已经上场的城邦
local iSrc, sCivB, sLdrB = -1, nil, nil
for j = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[j] end)
    pcall(function() pl = Players[j] end)
    if pc ~= nil and pl ~= nil then
        local civ, alive, lvl = nil, nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        pcall(function() lvl = pc:GetCivilizationLevelTypeName() end)
        if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and alive == true and civ ~= nil then
            pcall(function() sLdrB = pc:GetLeaderTypeName() end)
            iSrc, sCivB = j, civ
            break
        end
    end
end
print("  源城邦: slot " .. tostring(iSrc) .. "  " .. tostring(sCivB) .. "  领袖=" .. tostring(sLdrB))
local iB = -1
if iSrc >= 0 then
    local x2, y2, why2 = -1, -1, nil
    if ExposedMembers ~= nil and ExposedMembers.CSF ~= nil and ExposedMembers.CSF.FindFoundLocation ~= nil then
        local ok, a, b, c = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
        if ok then x2, y2, why2 = a, b, c end
    end
    print("  找地: (" .. tostring(x2) .. "," .. tostring(y2) .. ")")
    if x2 > 0 then
        local ok2, a2, b2, c2 = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCivB, x2, y2, nil, nil)
        print("  FoundCityStateByCiv ok=" .. tostring(ok2) .. " 返回=" .. tostring(a2)
              .. "," .. tostring(b2) .. "," .. tostring(c2))
        for j = 0, 63 do
            if j ~= iSrc then
                local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
                if pc ~= nil then
                    local civ, alive = nil, nil
                    pcall(function() civ = pc:GetCivilizationTypeName() end)
                    pcall(function() alive = Players[j]:IsAlive() end)
                    if civ == sCivB and alive == true then iB = j; break end
                end
            end
        end
    end
end
print("")
print("  (b) 副本槽位 = " .. tostring(iB))
if iB >= 0 then
    chk("IsAlive", function() return Players[iB]:IsAlive() end)
    chk("GetCivType（应与源一致）", function() return PlayerConfigurations[iB]:GetCivilizationTypeName() end)
    chk("GetLeader（应与源一致）", function() return PlayerConfigurations[iB]:GetLeaderTypeName() end)
    chk("GetCivLevel", function() return PlayerConfigurations[iB]:GetCivilizationLevelTypeName() end)
    chk("单位数", function() local n = 0; for _ in Players[iB]:GetUnits():Members() do n = n + 1 end; return n end)
    chk("副本后缀", function() return Game:GetProperty("CSF_CopySuffix_" .. tostring(iB)) end)
end

-- ===========================================================================
print("")
print("==============================================================")
print("=== 全场城邦总览 ===")
print("==============================================================")
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
            local civ, cn, sf, uni = nil, 0, nil, 0
            pcall(function() civ = pc:GetCivilizationTypeName() end)
            pcall(function() cn = pl:GetCities():GetCount() end)
            pcall(function() sf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
            pcall(function() for _ in pl:GetUnits():Members() do uni = uni + 1 end end)
            n = n + 1; nCity = nCity + cn
            print(string.format("  slot %2d  城市=%d  单位=%d  后缀=%-5s  %s",
                  j, cn, uni, tostring(sf), tostring(civ)))
        end
    end
end
print("  存活城邦 " .. n .. " 个，城市总数 " .. nCity)
print("")
print("★ 请点下一回合：看各城邦是否建城、是否崩溃")
print("=== 自测结束 ===")
