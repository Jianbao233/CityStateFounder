-- ===========================================================================
-- CityStateFounder / 城邦缔造者 — 官方城邦界面补丁（名字后缀）
-- 区段：InGameActions > ReplaceUIScript（LuaContext=CityStates）+ ImportFiles
--
-- 目的：允许「重复城邦」（同一 CivilizationType 被多个 minor 玩家共用）时，
--       在界面上用后缀区分它们（阿姆斯特丹 / 阿姆斯特丹 II / 阿姆斯特丹 III）。
--
-- 为什么用 UI 后缀而不是改数据：
--   - 两个 minor 玩家共用同一 CivilizationType 时，它们的名字数据本来就是同一个
--     LOC 键，无法从数据层区分（MirrorMap 的既有做法也是 UI 后缀）
--   - 官方城邦界面的 m_kCityStates 条目里有 iPlayer（玩家 ID）与 Name（显示名），
--     可以在渲染前按玩家 ID 追加后缀
--
-- 参考实现：CCB/ChineseCiv6BalanceMirrorMapDemo 的
--           UI/MirrorMapDemo_CityStatesPatch.lua（同一手法的既有先例）
-- ===========================================================================

include("CityStates");

print("[CSF] CSF_CityStatesPatch.lua loading (CityStates replacement)");

-- ---------------------------------------------------------------------------
-- 工具
-- ---------------------------------------------------------------------------
local function CSF_Safe(f, ...)
    local ok, v = pcall(f, ...);
    if ok then return v end;
    return nil;
end

-- 取某城邦玩家在本局的"重复序号"（同名城邦中的第几个）
--   序号 1 → 无后缀；序号 N>1 → 追加 LOC_CSF_SUFFIX_<N>
local function CSF_GetDuplicateIndex(iPlayerID)
    -- 该玩家的 CivilizationType
    local sCiv = CSF_Safe(function()
        return PlayerConfigurations[iPlayerID]:GetCivilizationTypeName();
    end);
    if sCiv == nil then return 1 end

    -- 统计所有存活 minor 中，CivType 相同且【玩家 ID 更小】的数量
    local iRank = 1;
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    for _, iOther in ipairs(tIDs) do
        if iOther < iPlayerID then
            local sOtherCiv = CSF_Safe(function()
                return PlayerConfigurations[iOther]:GetCivilizationTypeName();
            end);
            if sOtherCiv == sCiv then
                iRank = iRank + 1;
            end
        end
    end
    return iRank;
end

local function CSF_AppendSuffix(kCityState)
    if kCityState == nil or kCityState.iPlayer == nil then return false end
    if kCityState.Name == nil then return false end

    local iRank = CSF_GetDuplicateIndex(kCityState.iPlayer);
    if iRank <= 1 then return false end          -- 第一个不加后缀

    -- 支持到 III；再多就退化为数字
    local sSuffixTag = "LOC_CSF_SUFFIX_" .. tostring(iRank);
    local sSuffix = CSF_Safe(function() return Locale.Lookup(sSuffixTag) end);
    if sSuffix == nil or sSuffix == "" then
        sSuffix = " " .. tostring(iRank);
    end

    -- 防止重复追加
    local sName = tostring(kCityState.Name);
    if string.sub(sName, -string.len(sSuffix)) == sSuffix then
        return false;
    end

    kCityState.Name = sName .. sSuffix;
    return true;
end

function CSF_ApplyAllCityStateSuffixes(kCityStates)
    if type(kCityStates) ~= "table" then return 0 end
    local iCount = 0;
    for _, kCityState in pairs(kCityStates) do
        if type(kCityState) == "table" then
            if CSF_AppendSuffix(kCityState) then
                iCount = iCount + 1;
            end
        end
    end
    if iCount > 0 then
        print("[CSF] applied duplicate-name suffix to " .. tostring(iCount) .. " city-state(s)");
    end
    return iCount;
end

-- ---------------------------------------------------------------------------
-- 包裹原生入口（在数据取好之后、渲染之前追加后缀）
-- ---------------------------------------------------------------------------
local BASE_GetData = GetData;
function GetData()
    BASE_GetData();
    CSF_ApplyAllCityStateSuffixes(m_kCityStates);
end

local BASE_ViewList = ViewList;
function ViewList()
    CSF_ApplyAllCityStateSuffixes(m_kCityStates);
    BASE_ViewList();
end

local BASE_ViewCityState = ViewCityState;
function ViewCityState(iPlayer)
    CSF_ApplyAllCityStateSuffixes(m_kCityStates);
    BASE_ViewCityState(iPlayer);
end

print("[CSF] CSF_CityStatesPatch.lua ready");
