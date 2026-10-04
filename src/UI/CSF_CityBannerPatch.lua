-- ===========================================================================
-- CSF_CityBannerPatch.lua —— 城邦旗标兜底（★ 逐行照抄 XP2 版原函数）
-- ===========================================================================
-- 目的：让【中途建出来的城邦】旗标颜色正常，且不触发
--       `CityBannerManager: Called SetColor with nil value` → 引擎崩溃。
--
-- 根因：中途激活/新建的玩家【不在 UI 的颜色表里】→ UI.GetPlayerColors(slot)
--       返回 nil → 旗标代码把这个 nil 直接传给 SetColor() → 崩溃。
--
-- ── 三次走弯路的记录（务必别再犯）──────────────────────────────────────
--   ① 照抄 Base\Assets\UI\WorldView\CityBannerManager.lua 逐行重写
--      → 游戏实际加载的是 DLC\Expansion2\UI\CityBanners\CityBannerManager.lua
--      → 两版控件不同（Base 有 CityPopulation、XP2 没有）
--      → self.m_Instance.CityPopulation 是 nil → 每帧报错 → 城市面板消失
--   ② 给每个 SetColor 加 nil 守卫 → 不崩了，但旗标整个不显示
--      —— 因为漏了 XP2 版结尾的两句：
--           else self:UpdateColorOtherBannerTypes( backColor );
--           self:SetHealthBarColor();
--   ③ 想改成"包装 UI.GetPlayerColors" → 报 lReadOnlyError
--      —— UI.GetPlayerColors 是只读的，不能覆盖
--
--   → 最终方案：替换 CityBannerManager，但 UpdateColor 逐行照抄 XP2 版。
--
-- 基准文件（★ 以这个为准，不是 Base 那个）：
--   <游戏目录>\DLC\Expansion2\UI\CityBanners\CityBannerManager.lua:816-864
-- ===========================================================================

include("CSF_CopyRegistry");

if CSF_CityBannerManager_BaseLoaded ~= true then
    CSF_CityBannerManager_BaseLoaded = true;
    include("CityBannerManager");
end

local function CSF_GetBannerColors(playerID)
    local backColor, frontColor = UI.GetPlayerColors(playerID);
    if backColor ~= nil and frontColor ~= nil then
        return backColor, frontColor;
    end

    local sCiv = nil;
    pcall(function()
        if CSF_GetCopySource ~= nil then sCiv = CSF_GetCopySource(playerID) end
        if sCiv == nil and CSF_GetGameProp ~= nil then
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
                        b2, f2 = UI.GetPlayerColors(i);
                    end
                end);
                if b2 ~= nil and f2 ~= nil then
                    print("[CSF] banner color: slot " .. tostring(playerID) ..
                          " 用同文明槽 " .. tostring(i) .. " 的颜色兜底");
                    return b2, f2;
                end
            end
        end
        local b3, f3 = nil, nil;
        pcall(function() b3, f3 = UI.GetPlayerColorValues(sCiv, 0) end);
        if b3 ~= nil and f3 ~= nil then
            print("[CSF] banner color: slot " .. tostring(playerID) ..
                  " 用文明色兜底（" .. tostring(sCiv) .. "）");
            return b3, f3;
        end
    end

    print("[CSF] banner color: slot " .. tostring(playerID) .. " 兜底失败，用安全色");
    return 0xFF202020, 0xFFC0C0C0;
end

-- ★ 逐行照抄 XP2 版 CityBannerManager.lua:816-864；唯一改动是取色那一行
function CityBanner:UpdateColor()
    local backColor, frontColor = CSF_GetBannerColors( self.m_Player:GetID() );
    local darkerBackColor :number = UI.DarkenLightenColor(backColor,-85,238);

    if (self.m_Type == BANNERTYPE_CITY_CENTER) then
        self.m_Instance.CityBannerFill:SetColor( backColor );
        self.m_Instance.CityBannerFillOver:SetColor( frontColor );
        self.m_Instance.CityBannerFillOut:SetColor( frontColor );
        self.m_Instance.CityName:SetColor( frontColor, 0 );
        self.m_Instance.CityName:SetColor( darkerBackColor, 1 );
        if self.m_CivIconInstance then
            self.m_CivIconInstance.Icon:SetColor( frontColor );
        end
    elseif (self.m_Type == BANNERTYPE_AERODROME) then
        if self.m_Instance.AerodromeUnitsButton_Base ~= nil then
            self.m_Instance.AerodromeUnitsButton_Base:SetColor( backColor );
            self.m_Instance.AerodromeMouseOver:SetColor( frontColor );
            self.m_Instance.AerodromeMouseOut:SetColor( frontColor );
            self.m_Instance.AerodromeUnitsButtonIcon:SetColor( frontColor );
        end
    elseif (self.m_Type == BANNERTYPE_MISSILE_SILO) then
        if self.m_Instance.Banner_Base ~= nil then
            self.m_Instance.Banner_Base:SetColor( backColor );
            self.m_Instance.NukeCountLabel:SetColor( frontColor );
            self.m_Instance.ThermoNukeCountLabel:SetColor( frontColor );
        end
    elseif (self.m_Type == BANNERTYPE_ENCAMPMENT) then
        if self.m_Instance.Banner_Base ~= nil then
            self.m_Instance.Banner_Base:SetColor( backColor );
        end
    elseif (self.m_Type == BANNERTYPE_OTHER_DISTRICT) then
        if self.m_Instance.Banner_Base ~= nil then
            self.m_Instance.Banner_Base:SetColor( backColor );
        end
    elseif (self.m_Type == BANNERTYPE_MOUNTAIN_TUNNEL) then
        if self.m_Instance.Banner_Base ~= nil then
            self.m_Instance.Banner_Base:SetColor( backColor );
        end
    elseif (self.m_Type == BANNERTYPE_QHAPAQ_NAN) then
        if self.m_Instance.Banner_Base ~= nil then
            self.m_Instance.Banner_Base:SetColor( backColor );
        end
    else
        self:UpdateColorOtherBannerTypes( backColor );
    end

    self:SetHealthBarColor();
end

print("[CSF] CSF_CityBannerPatch.lua loaded（逐行照抄 XP2 版 UpdateColor）");