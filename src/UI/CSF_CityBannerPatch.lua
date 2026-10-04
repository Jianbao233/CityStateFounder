-- ===========================================================================
-- CSF_CityBannerPatch.lua —— 城邦旗标兜底（颜色 + 副本名字后缀）
-- ===========================================================================
-- 目的：让【中途建出来的城邦副本】也能正常显示，不触发
--       `CityBannerManager: Called SetColor with nil value` → 引擎崩溃。
--
-- 根因（实测 + 逆向）：
--   · 中途激活/新建的玩家**不在 UI 的颜色表里** → `UI.GetPlayerColors(slot)` 返回 nil
--   · 旗标代码 `CityBanner:UpdateColor()` 直接把这个 nil 传给 `SetColor()` → 崩溃
--   · 引擎日志：`CityBannerManager: Called SetColor with nil value.`（4 次后崩）
--
-- 手法来源：CCB MirrorMap 的 UI\CityBannerManager_Mirror.lua:7-20
--   include("CityBannerManager") 后【覆盖】CityBanner:UpdateColor()，
--   在 UI.GetPlayerColors 返回 nil 时用【源城邦的颜色】替补。
--
-- ⚠️⚠️ 本文件的 UpdateColor 是**逐行照抄原版**
--      F:\...\Base\Assets\UI\WorldView\CityBannerManager.lua:716-754，
--      只改两处：① 颜色来源走 CSF_GetBannerColors（含兜底）
--                ② 调用 SetColor 前把 nil 换成安全色
--      原版的 5 个分支（CITY_CENTER / AERODROME / MISSILE_SILO /
--      ENCAMPMENT / OTHER_DISTRICT）与每一行 SetColor **一个都不能少**，
--      否则会出现"人口数字不上色""区域旗标不上色"之类的视觉缺陷。
-- ===========================================================================

include("CSF_CopyRegistry");     -- 共用小工具（读 Game 属性 + 副本判定）

-- 加载原版 CityBannerManager（幂等）
if CSF_CityBannerManager_BaseLoaded ~= true then
    CSF_CityBannerManager_BaseLoaded = true;
    include("CityBannerManager");
end

-- ---------------------------------------------------------------------------
-- 颜色来源：UI 表里有就用；没有（副本）就按"源城邦 → 文明色"逐级兜底
-- ---------------------------------------------------------------------------
local function CSF_GetBannerColors(playerID)
    local backColor, frontColor = UI.GetPlayerColors(playerID);
    if backColor ~= nil and frontColor ~= nil then
        return backColor, frontColor;            -- 正常情况，不动
    end

    -- 只有"副本"才兜底；不是副本就原样返回（保持原版行为）
    local sSourceCiv = CSF_GetCopySource(playerID);
    if sSourceCiv == nil then
        return backColor, frontColor;
    end

    -- ① 找一个【正在使用该源文明】的玩家，用它的颜色
    for i = 0, 63 do
        if i ~= playerID then
            local pPlayer = Players[i];
            if pPlayer ~= nil then
                local sCiv = nil;
                pcall(function()
                    sCiv = PlayerConfigurations[i]:GetCivilizationTypeName();
                end);
                if sCiv == sSourceCiv then
                    local b2, f2 = UI.GetPlayerColors(i);
                    if b2 ~= nil and f2 ~= nil then
                        print("[CSF] banner: 副本 " .. tostring(playerID) ..
                              " 用源城邦槽 " .. tostring(i) .. " 的颜色兜底");
                        return b2, f2;
                    end
                end
            end
        end
    end

    -- ② 再兜底：按【文明】取色（城邦颜色是按文明定义的，实测可用）
    local b3, f3 = nil, nil;
    pcall(function()
        b3, f3 = UI.GetPlayerColorValues(sSourceCiv, 0);
    end);
    if b3 ~= nil and f3 ~= nil then
        print("[CSF] banner: 副本 " .. tostring(playerID) ..
              " 用文明色兜底（" .. tostring(sSourceCiv) .. "）");
        return b3, f3;
    end

    print("[CSF] banner: ⚠️ 副本 " .. tostring(playerID) ..
          " 三级兜底都拿不到颜色（源=" .. tostring(sSourceCiv) .. "）");
    return backColor, frontColor;
end

-- ---------------------------------------------------------------------------
-- 覆盖 CityBanner:UpdateColor —— 逐行照抄原版，只换颜色来源 + 加 nil 保险
-- ---------------------------------------------------------------------------
function CityBanner:UpdateColor()
    local playerID:number = self.m_Player:GetID();
    local backColor:number, frontColor:number = CSF_GetBannerColors(playerID);

    -- ★ 最后一道保险：任何一个是 nil 就用安全色，绝不让 SetColor 拿到 nil（那是崩溃点）
    if backColor == nil then backColor = 0xFF202020; end
    if frontColor == nil then frontColor = 0xFFC0C0C0; end

    local darkerBackColor:number = UI.DarkenLightenColor(backColor, (-85), 238);

    -- ⚠️⚠️⚠️ 【2026-10-04 重大修正】每个 SetColor 都必须判 nil！
    --
    --   踩到的坑：我原先照抄的是
    --       F:\...\Base\Assets\UI\WorldView\CityBannerManager.lua
    --   但游戏实际加载的是【资料片 2 的那一份】：
    --       F:\...\DLC\Expansion2\UI\CityBanners\CityBannerManager.lua
    --   两者结构不同（XP2 版没有 m_Instance.CityPopulation 之类），
    --   于是 `self.m_Instance.CityPopulation:SetColor(...)` 直接报
    --       Runtime Error: CSF_CityBannerPatch.lua:105: ...
    --   而 UpdateColor 每帧都跑 → 报错刷屏 → 旗标/面板系统全坏
    --   （用户实测：点下一回合后城市面板消失）。
    --
    --   → 结论：**不要假设控件存在**。所有 SetColor 一律走 CSF_SetColorIfAny，
    --     缺控件就静默跳过。这样无论加载 Base 还是 XP2 的版本都不会崩。
    local function CSF_SetColorIfAny(pControl, color, layer)
        if pControl == nil then return end;
        if layer == nil then
            pControl:SetColor( color );
        else
            pControl:SetColor( color, layer );
        end
    end

    if (self.m_Type == BANNERTYPE_CITY_CENTER) then
        CSF_SetColorIfAny( self.m_Instance.CityBannerFill,     backColor );
        CSF_SetColorIfAny( self.m_Instance.CityBannerFillOver, frontColor );
        CSF_SetColorIfAny( self.m_Instance.CityBannerFillOut,  frontColor );
        CSF_SetColorIfAny( self.m_Instance.CityName,           frontColor, 0 );
        CSF_SetColorIfAny( self.m_Instance.CityName,           darkerBackColor, 1 );
        -- ↓ 这两行在 Base 版里有、XP2 版里没有 → 必须判 nil
        CSF_SetColorIfAny( self.m_Instance.CityPopulation,     frontColor, 0 );
        CSF_SetColorIfAny( self.m_Instance.CityPopulation,     backColor, 1 );
        if not self:IsTeam() then
            CSF_SetColorIfAny( self.m_Instance.CivIcon,        frontColor );
        end
    elseif (self.m_Type == BANNERTYPE_AERODROME) then
        CSF_SetColorIfAny( self.m_Instance.AerodromeUnitsButton_Base, backColor );
        CSF_SetColorIfAny( self.m_Instance.AerodromeMouseOver,        frontColor );
        CSF_SetColorIfAny( self.m_Instance.AerodromeMouseOut,         frontColor );
        CSF_SetColorIfAny( self.m_Instance.AerodromeUnitsButtonIcon,  frontColor );
    elseif (self.m_Type == BANNERTYPE_MISSILE_SILO) then
        CSF_SetColorIfAny( self.m_Instance.Banner_Base,          backColor );
        CSF_SetColorIfAny( self.m_Instance.NukeCountLabel,       frontColor );
        CSF_SetColorIfAny( self.m_Instance.ThermoNukeCountLabel, frontColor );
    elseif (self.m_Type == BANNERTYPE_ENCAMPMENT) then
        CSF_SetColorIfAny( self.m_Instance.Banner_Base,          backColor );
    elseif (self.m_Type == BANNERTYPE_OTHER_DISTRICT) then
        CSF_SetColorIfAny( self.m_Instance.Banner_Base,          backColor );
    end
end

print("[CSF] CSF_CityBannerPatch.lua loaded（旗标颜色兜底，逐行对齐原版）");
