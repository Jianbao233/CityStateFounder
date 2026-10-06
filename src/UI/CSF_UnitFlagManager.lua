-- ===========================================================================
-- CSF_UnitFlagManager.lua —— 单位旗标颜色兜底
-- ===========================================================================
-- 为什么需要：单位旗标走的也是 `UI.GetPlayerColors(playerID)`（Base 版 493 行）。
--   【中途激活的城邦】不在 UI 的玩家颜色表里 → 返回 nil →
--   `instance.FlagBase:SetColor(nil)` → 引擎原生层读 NULL+0xc → 崩溃。
--   城邦迟早会造出单位，所以这条路径必须堵上。
--
--   做法与 CSF_CityBannerPatch.lua 完全一致：
--     ① include 当前生效的 UnitFlagManager（拿到 UnitFlag 类与其它函数）
--     ② 只重写 `UnitFlag.SetColor`，把取色那一行换成 CSF_SafePlayerColors
--     ③ 其余逐行照抄 Base\Assets\UI\UnitFlagManager.lua:492-508
--
-- 基准文件：<游戏目录>\Base\Assets\UI\UnitFlagManager.lua:492-508
-- ===========================================================================

include("CSF_UICommon");

if CSF_UnitFlagManager_BaseLoaded ~= true then
    CSF_UnitFlagManager_BaseLoaded = true;
    include("UnitFlagManager");
end

-- ★ 逐行照抄 Base 版 UnitFlag.SetColor；唯一改动是取色那一行
function UnitFlag.SetColor( self )
	local primaryColor, secondaryColor = CSF_SafePlayerColors( self.m_Player:GetID() );

	local instance:table = self.m_Instance;
	instance.FlagBase:SetColor( primaryColor );
	instance.HealthBarBG:SetColor( primaryColor );
	instance.UnitIcon:SetColor( secondaryColor );
	instance.FlagMouseOut:SetColor( secondaryColor );
	instance.FlagMouseOver:SetColor( secondaryColor );

	-- Set air unit list button color
	instance = instance.AirUnitInstance;
	if instance then
		instance.AirUnitListButton_Base:SetColor( primaryColor );
		instance.AirUnitListButtonIcon:SetColor( secondaryColor );
	end
end

print("[CSF] CSF_UnitFlagManager.lua loaded（单位旗标 nil 颜色兜底）");
