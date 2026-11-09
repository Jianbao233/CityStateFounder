-- ===========================================================================
-- CSF_UICommon.lua —— UI 侧共享：**安全取玩家颜色**（绝不返回 nil）
-- ===========================================================================
-- 背景（2026-10-07 实测确认，这是"白色旗标 → 崩游戏"的真正根因）：
--
--   `UI.GetPlayerColors(playerID)` 读的是 **UI 自己的一张「玩家 → 颜色」表**，
--   这张表在【开局加载时】就建好了，之后**再也不刷新**（实测：连过回合都不刷新）。
--   所以我们【对局中途激活的城邦槽】不在表里 → 该函数返回 **nil**。
--
--   证据（本机实测，slot 45 = 中途建出来的安塔那那利佛）：
--       UI.GetPlayerColors(6)  -> primary=-15198184 secondary=-16656137   （真城邦）
--       UI.GetPlayerColors(7)  -> primary=-15198184
--       UI.GetPlayerColors(45) -> primary=nil        secondary=nil        ← 我们
--       UI.GetPlayerColorValues("CIVILIZATION_ANTANANARIVO", 0) -> -15198184
--     ⇒ 真城邦的主色就是 -15198184，而我们的槽取不到 → 旗标代码把 nil 传给
--       `SetColor()` → 引擎原生层读 NULL+0xc → **崩溃**。
--
--   ⚠️ `UI.GetPlayerColors` 是**只读**的（覆写报 lReadOnlyError），
--      所以只能在【每个调用点】做兜底。本文件把兜底逻辑集中成一个函数，
--      由 CSF_CityBannerPatch.lua / CSF_UnitFlagManager.lua 共用。
--
--   兜底顺序：
--     ① UI.GetPlayerColors 有值 → 直接用（正常玩家/正常城邦走这条）
--     ② 同文明的其他槽（副本场景：能力与颜色全部复用源城邦）
--     ③ UI.GetPlayerColorValues(文明类型, 0) → 该文明的官方配色
--        （所有城邦都返回同一个 -15198184，即城邦主色 —— 与官方城邦完全一致）
--     ④ 保险色（深灰/浅灰）
-- ===========================================================================

include("CSF_CopyRegistry");

-- 捕获引擎接口，避免 CityStates 私有 UI 适配层回调本函数时递归。
local CSF_NativeGetPlayerColors = UI.GetPlayerColors;
local CSF_NativeGetPlayerColorValues = UI.GetPlayerColorValues;

-- Runtime GameCore configuration and the frontend configuration are separate
-- objects. A zero-opening closed slot is empty in the frontend even after
-- native registration. Use official setters on the real frontend objects;
-- do not replace PlayerConfigurations getters or manufacture HasMet/envoys.
function CSF_SynchronizeFoundedIdentities()
    local api = ExposedMembers and ExposedMembers.CSF;
    local getter = api and (api.GetPublishedIdentities or api.GetFoundedIdentities);
    if getter == nil then return true; end
    local ok, rows = pcall(getter);
    if not ok or type(rows) ~= "table" then return false; end
    local colorsChanged = false;
    local colorsMissing = false;
    for _, row in ipairs(rows) do
        if type(row.PlayerID) ~= "number" or row.PlayerID < 0 or row.PlayerID >= 62 or
           type(row.Civ) ~= "string" or type(row.Leader) ~= "string" then return false; end
        local success, consistent = pcall(function()
            local cfg = PlayerConfigurations[row.PlayerID];
            if cfg:GetLeaderTypeName() ~= row.Leader then cfg:SetLeaderTypeName(row.Leader); end
            if cfg:GetCivilizationTypeName() ~= row.Civ then cfg:SetCivilizationTypeName(row.Civ); end
            if type(row.ShortName) == "string" then
                if cfg:GetCivilizationShortDescription() ~= row.ShortName then cfg:SetValue("CIVILIZATION_SHORT_DESCRIPTION", row.ShortName); end
                if cfg:GetCivilizationDescription() ~= row.Description then cfg:SetValue("CIVILIZATION_DESCRIPTION", row.Description); end
                if cfg:GetValue("CIVILIZATION_ADJECTIVE") ~= row.Adjective then cfg:SetValue("CIVILIZATION_ADJECTIVE", row.Adjective); end
                if cfg:GetLeaderName() ~= row.ShortName then cfg:SetLeaderName(row.ShortName); end
                if cfg:GetCivilizationShortDescription() ~= row.ShortName or cfg:GetCivilizationDescription() ~= row.Description then return false; end
            end
            -- Native setters 0x16B1B0 / 0x169CD0 use these exact keys;
            -- the static key initializer is 0x001F20 in the pinned XP2 core.
            local level = CivilizationLevelTypes.CIVILIZATION_LEVEL_CITY_STATE;
            if cfg:GetCivilizationLevelTypeID() ~= level then
                cfg:SetValue("CIVILIZATION_LEVEL_TYPE_NAME", "CIVILIZATION_LEVEL_CITY_STATE");
                cfg:SetValue("CIVILIZATION_LEVEL_TYPE_ID", level);
            end
            if cfg:GetSlotStatus() ~= SlotStatus.SS_COMPUTER then cfg:SetSlotStatus(SlotStatus.SS_COMPUTER); end
            if type(row.Color) == "number" and cfg:GetValue("PLAYER_COLOR_TYPE") ~= row.Color then
                cfg:SetValue("PLAYER_COLOR_TYPE", row.Color);
                if cfg:GetValue("PLAYER_COLOR_TYPE") ~= row.Color then return false; end
                colorsChanged = true;
            end
            if type(row.Color) == "number" then
                local back, front = CSF_NativeGetPlayerColors(row.PlayerID);
                if back == nil or front == nil then colorsMissing = true; end
            end
            return cfg:GetCivilizationTypeName() == row.Civ and
                   cfg:GetLeaderTypeName() == row.Leader and cfg:GetCivilizationLevelTypeID() == level and
                   cfg:GetSlotStatus() == SlotStatus.SS_COMPUTER;
        end);
        if not success or not consistent then return false; end
    end
    if colorsChanged or colorsMissing then
        local rebuilt = pcall(function() UI.RefreshColorSet(); UI.RebuildColorDB(); end);
        if not rebuilt then return false; end
    end
    for _, row in ipairs(rows) do
        if type(row.Color) == "number" then
            local success, back, front = pcall(CSF_NativeGetPlayerColors, row.PlayerID);
            if not success or back == nil or front == nil then return false; end
        end
    end
    return true;
end

--- 安全取某个玩家的 (primaryColor, secondaryColor)；**保证非 nil**。
function CSF_SafePlayerColors(playerID)
    if playerID == nil then
        return 0xFF202020, 0xFFC0C0C0;
    end

    -- ① 正常路径
    local backColor, frontColor = nil, nil;
    pcall(function() backColor, frontColor = CSF_NativeGetPlayerColors(playerID) end);
    if backColor ~= nil and frontColor ~= nil then
        return backColor, frontColor;
    end

    -- ② 同文明的其他槽（副本）
    local sCiv = nil;
    pcall(function()
        sCiv = CSF_GetCopySource(playerID);
        if sCiv == nil then
            sCiv = CSF_GetGameProp("CSF_Created_" .. tostring(playerID));
        end
        if sCiv == nil then
            sCiv = PlayerConfigurations[playerID]:GetCivilizationTypeName();
        end
    end);
    if sCiv ~= nil then
        for i = 0, 63 do
            if i ~= playerID then
                local b2, f2 = nil, nil;
                pcall(function()
                    if PlayerConfigurations[i]:GetCivilizationTypeName() == sCiv then
                        b2, f2 = CSF_NativeGetPlayerColors(i);
                    end
                end);
                if b2 ~= nil and f2 ~= nil then
                    return b2, f2;
                end
            end
        end

        -- ③ 该文明的官方配色（城邦统一返回城邦主色）
        local b3, f3 = nil, nil;
        pcall(function() b3, f3 = CSF_NativeGetPlayerColorValues(sCiv, 0) end);
        if b3 ~= nil then
            if f3 == nil then f3 = b3 end;
            return b3, f3;
        end
    end

    -- ④ 保险色
    return 0xFF202020, 0xFFC0C0C0;
end

CSF_SynchronizeFoundedIdentities();
print("[CSF] CSF_UICommon.lua loaded（安全取色 CSF_SafePlayerColors）");
