-- ===========================================================================
-- CSF_CreateCityState.lua —— 对局中「实时创建指定城邦」
-- ===========================================================================
-- ⭐ 2026-10-04 实测突破：把【存档池子里、但未出现在玩家槽位】的城邦
--    在对局中实时激活，并建到地图上任意位置。
--
-- ── 三步公式（零 DLL、纯现成 Lua API）──────────────────────────────────
--   ① pm:SetPlayerSlotStatus(slot, 1)        -- 用【引擎内部枚举】1 = AI
--   ② pm:InitializePlayer(slot)              -- 真正建玩家对象
--   ③ Players[slot]:GetCities():Create(x, y) -- 建在指定格
--
-- ── 为什么之前失败（逆向结论，见 docs/DLL实时激活城邦_逆向进展.md）──────
--   引擎内部函数 FUN_180617370 有一道门：
--       uVar1 = FUN_18016a2b0(player);                       -- 取槽位状态
--       if (((uVar1 & 0xfffffffc) != 0) || (uVar1 == 2)) return;   -- 拒绝
--   预注册城邦槽的状态是 **5**，`5 & 0xfffffffc = 4 ≠ 0` → 被静默拒绝。
--   所以 InitializePlayer 看着返回 true，实际什么都没做。
--   设成 1 后通过。
--
--   ⚠️ 引擎内部枚举：0=Open 1=AI 2=Closed 3=Human 4=Observer
--      （与 Lua 层暴露的 SS_CLOSED/SS_COMPUTER/SS_OBSERVER/SS_OPEN/SS_TAKEN
--        **不是一套** —— 这是此前 SetSlotStatus "实测无效"的根因）
--
-- ── 实测证据 ────────────────────────────────────────────────────────────
--   slot 36 CIVILIZATION_LA_VENTA（拉文塔）：
--     激活前 GetSlotStatus=5 alive=false GetCities=nil
--     三步后 alive=true、cities=1、首都"拉文塔"(19,5)、人口 1、所有者 36
--   原生性：IsMajor=false、GetDiplomacy() 有效、GetInfluence() 有效
--
-- ── 已知缺陷 ────────────────────────────────────────────────────────────
--   ⚠️ **颜色没绑上**：`UI.GetPlayerColors(slot)` 返回 nil。
--      但文明本身有颜色定义（`UI.GetPlayerColorValues(civType,0)` 有值）。
--      缺的是「槽位 → 颜色」的绑定，尚在追（见文档 §10.4）。
--      影响：旗标无颜色，**不影响功能**。
-- ===========================================================================

-- 引擎内部的槽位状态枚举（**不是** Lua 的 SS_*）
CSF_SLOT_OPEN     = 0;
CSF_SLOT_AI       = 1;
CSF_SLOT_CLOSED   = 2;
CSF_SLOT_HUMAN    = 3;
CSF_SLOT_OBSERVER = 4;

--- 找一个「池子里有、但未激活」的城邦槽。
-- @param sCivFilter  可选：只找这个文明类型
-- @return slot, civType, slotStatus   找不到返回 -1
function CSF_FindInactiveCityStateSlot(sCivFilter)
    local pm = nil;
    pcall(function() pm = WorldBuilder.PlayerManager() end);
    if pm == nil then return -1, nil, nil end;

    for i = 15, 63 do
        local p, pc = nil, nil;
        pcall(function() p = Players[i] end);
        pcall(function() pc = PlayerConfigurations[i] end);
        if p ~= nil and pc ~= nil then
            local sCiv, bAlive = nil, nil;
            pcall(function() sCiv = pc:GetCivilizationTypeName() end);
            pcall(function() bAlive = p:IsAlive() end);
            if sCiv ~= nil and sCiv ~= "" and bAlive == false then
                -- 必须是城邦文明（枚举 GameInfo 匹配，不用索引取值）
                local bIsCityState = false;
                pcall(function()
                    for row in GameInfo.Civilizations() do
                        if row.CivilizationType == sCiv
                           and row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
                            bIsCityState = true;
                            break;
                        end
                    end
                end);
                if bIsCityState then
                    if sCivFilter == nil or sCivFilter == sCiv then
                        -- 该文明是否已被别的【已激活】槽占用（引擎不允许重复）
                        local bUsed = false;
                        for j = 0, 63 do
                            if j ~= i then
                                local pc2 = nil;
                                pcall(function() pc2 = PlayerConfigurations[j] end);
                                if pc2 ~= nil then
                                    local c2, a2 = nil, nil;
                                    pcall(function() c2 = pc2:GetCivilizationTypeName() end);
                                    pcall(function() a2 = Players[j]:IsAlive() end);
                                    if c2 == sCiv and a2 == true then bUsed = true; break end;
                                end
                            end
                        end
                        if not bUsed then
                            local iStatus = nil;
                            pcall(function() iStatus = pm:GetSlotStatus(i) end);
                            return i, sCiv, iStatus;
                        end
                    end
                end
            end
        end
    end
    return -1, nil, nil;
end

--- ⭐ 对局中实时激活一个城邦槽（池子里有、但未激活的那种）。
-- @param iSlot  目标槽号（来自 CSF_FindInactiveCityStateSlot）
-- @return true / false
function CSF_ActivateCityStateSlot(iSlot)
    local pm = nil;
    pcall(function() pm = WorldBuilder.PlayerManager() end);
    if pm == nil then return false end;
    if iSlot == nil or iSlot < 0 then return false end;

    -- ① 设槽位状态为 AI（内部枚举 1）—— 绕过 FUN_180617370 的门
    local ok1 = pcall(function() pm:SetPlayerSlotStatus(iSlot, CSF_SLOT_AI) end);
    if not ok1 then return false end;

    -- ② 初始化玩家对象
    local ok2 = pcall(function() pm:InitializePlayer(iSlot) end);
    if not ok2 then return false end;

    -- ③ 复查
    local bAlive, pCities = nil, nil;
    pcall(function() bAlive = Players[iSlot]:IsAlive() end);
    pcall(function() pCities = Players[iSlot]:GetCities() end);
    if bAlive ~= true or pCities == nil then return false end;

    print("[CSF] 城邦槽 " .. tostring(iSlot) .. " 已激活（" ..
          tostring(PlayerConfigurations[iSlot]:GetCivilizationTypeName()) .. "）");
    return true;
end

--- ⭐⭐ 一站式：在 (iX, iY) 实时创建一个指定的城邦。
-- @param sCivType  目标城邦文明（如 "CIVILIZATION_LA_VENTA"）；nil = 任意一个未激活的
-- @param iX, iY    目标格
-- @return true / false
function CSF_CreateCityStateAt(sCivType, iX, iY)
    local iSlot, sCiv = CSF_FindInactiveCityStateSlot(sCivType);
    if iSlot < 0 then
        print("[CSF] 找不到可激活的城邦槽（" .. tostring(sCivType) .. "）");
        return false;
    end
    if not CSF_ActivateCityStateSlot(iSlot) then
        print("[CSF] 激活失败 slot=" .. tostring(iSlot));
        return false;
    end
    local ok, pCity = pcall(function()
        return Players[iSlot]:GetCities():Create(iX, iY);
    end);
    if not ok or pCity == nil then
        print("[CSF] 建城失败 slot=" .. tostring(iSlot));
        return false;
    end
    print("[CSF] ✅ 城邦 " .. tostring(sCiv) .. " 已建在 (" ..
          tostring(iX) .. "," .. tostring(iY) .. ")");
    return true, iSlot, sCiv;
end

-- 暴露给其它脚本 / 调试用
ExposedMembers = ExposedMembers or {};
ExposedMembers.CSF_CreateCityState = ExposedMembers.CSF_CreateCityState or {};
ExposedMembers.CSF_CreateCityState.CreateAt            = CSF_CreateCityStateAt;
ExposedMembers.CSF_CreateCityState.ActivateSlot        = CSF_ActivateCityStateSlot;
ExposedMembers.CSF_CreateCityState.FindInactiveSlot    = CSF_FindInactiveCityStateSlot;

print("[CSF] CSF_CreateCityState.lua loaded（实时创建城邦：三步公式已就绪）");
