-- 保留官方 XP2 城邦交互，适配颜色、副本名称、BCS任务布局和运行期新增队伍。
if CSF_CityStates_BaseLoaded == true then return; end

include("CSF_UICommon");
-- UI 引擎对象成员只读，但当前 Lua Context 的 UI 全局可以代理。
-- 仅本面板使用安全取色，其余 API 原样转给引擎；不改引擎对象或其它 Context。
local CSF_NativeUI = UI;
UI = setmetatable({GetPlayerColors = CSF_SafePlayerColors}, {__index = CSF_NativeUI});
include("CityStates_Expansion2");
CSF_CityStates_BaseLoaded = true;

-- CCB Toolkits' BCS imports CityStates.xml independently of ReplaceUIScript.
-- Its row replaces QuestIcon with CuiCityStateQuest. Keep the official data
-- and callbacks, but adapt that real text control instead of mixing the XML
-- with a script which immediately indexes a missing QuestIcon (Lua.log:877).
-- InstanceManager and the instance tables are local to this Lua context.
if InstanceManager ~= nil and InstanceManager.GetInstance ~= nil then
    local baseGetInstance = InstanceManager.GetInstance;
    function InstanceManager:GetInstance(...)
        local instance = baseGetInstance(self, ...);
        if self.m_InstanceName == "CityStateRowInstance" and instance.QuestIcon == nil and
           instance.CuiCityStateQuest ~= nil then
            local label = instance.CuiCityStateQuest;
            local grid = instance.CuiQuestGrid or label;
            local questHidden = true;
            instance.QuestIcon = {
                SetHide = function(_, hidden)
                    questHidden = hidden;
                    grid:SetHide(hidden);
                    if hidden then label:SetText(""); end
                end,
                SetToolTipString = function(_, text)
                    -- SetHide is called first, as in the official row renderer.
                    if not questHidden then label:SetText(text); end
                    label:SetToolTipString(text);
                end
            };
        end
        return instance;
    end
end

-- Teams is an engine snapshot: runtime-created slots can have a team absent
-- from it. A context-local view supplies actual members from live config;
-- no game team assignment or native Teams object is changed. Negative team
-- IDs mean unassigned and must never group unrelated city states together.
local CSF_NativeTeams = Teams;
Teams = setmetatable({}, {__index = function(_, teamID)
    if type(teamID) ~= "number" or teamID < 0 then return {}; end
    local native = CSF_NativeTeams and CSF_NativeTeams[teamID];
    if native ~= nil then return native; end
    local members = {};
    if PlayerManager ~= nil and PlayerManager.GetAliveIDs ~= nil then
        for _, playerID in ipairs(PlayerManager.GetAliveIDs()) do
            local cfg = PlayerConfigurations[playerID];
            if cfg ~= nil and cfg:GetTeam() == teamID then
                members[#members + 1] = playerID;
            end
        end
    end
    return members;
end});

local CSF_BaseGetData = GetData;
function GetData(...)
    if not CSF_SynchronizeFoundedIdentities() then
        error("CSF frontend identity synchronization unconfirmed");
    end
    return CSF_BaseGetData(...);
end

local function CSF_NormalizeCityStateName(entry)
    if type(entry) ~= "table" or entry.iPlayer == nil then return; end
    local suffix = CSF_GetCopySuffix(entry.iPlayer);
    if suffix ~= nil and suffix ~= "" then
        entry.Name = CSF_ApplyCopySuffix(Locale.Lookup(entry.Name), entry.iPlayer);
    end
end

local CSF_BaseAddCityStateRow = AddCityStateRow;
if CSF_BaseAddCityStateRow ~= nil then
    function AddCityStateRow(entry)
        CSF_NormalizeCityStateName(entry);
        return CSF_BaseAddCityStateRow(entry);
    end
end

-- 详情页左侧列也把缓存条目传给此官方函数，直接打开详情时同样可补后缀。
local CSF_BaseGetRelationshipPip = GetRelationshipPipAtlasPieces;
if CSF_BaseGetRelationshipPip ~= nil then
    function GetRelationshipPipAtlasPieces(entry)
        CSF_NormalizeCityStateName(entry);
        return CSF_BaseGetRelationshipPip(entry);
    end
end

print("[CSF] CSF_CityStatesPatch.lua loaded (context-local color/quest/team adapter 2026-10-23)");
