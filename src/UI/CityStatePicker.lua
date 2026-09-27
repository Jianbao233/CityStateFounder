
include("InstanceManager");
include("PlayerSetupLogic");
include("Civ6Common");

-- ===========================================================================
-- CONSTANTS
-- ===========================================================================

local XP2_RULESETUP:string = "RULESET_EXPANSION_2";
local XP1_RULESETUP:string = "RULESET_EXPANSION_1";

-- ===========================================================================
-- Members
-- ===========================================================================

local m_pItemIM:table = InstanceManager:new("ItemInstance",	"Button", Controls.ItemsPanel);

local m_kParameter:table = nil		-- Reference to the parameter being used. 
local m_kSelectedValues:table = nil	-- Table of string->boolean that represents checked off items.
local m_kItemList:table = nil;		-- Table of controls for select all/none

local m_bInvertSelection:boolean = false;

local m_kCityStateDataCache:table = {};

local m_kCityStateCountParam:table = nil;

local m_RulesetType:string = "";

local m_numSelected:number = 0;

-- Track the number of city-states to spawn when opening the picker
-- Used to revert to that number in case the user modifies the parameter then backs out of the picker
local m_OriginalCityStateCount:number = 0;

-- ===========================================================================
function Close()	
	-- Clear any temporary global variables.
	m_kParameter = nil;
	m_kSelectedValues = nil;

	ContextPtr:SetHide(true);
end

-- ===========================================================================
function IsItemSelected(item: table) 
	return m_kSelectedValues[item.Value] == true;
end

-- ===========================================================================
function OnBackButton()
	Close();
	LuaEvents.CityStatePicker_SetParameterValue(m_kCityStateCountParam.ParameterId, m_OriginalCityStateCount);
end

-- ===========================================================================
function OnConfirmChanges()
	-- Generate sorted list from selected values.
	local values = {}
	for k,v in pairs(m_kSelectedValues) do
		if(v) then
			table.insert(values, k);
		end
	end

	LuaEvents.CityStatePicker_SetParameterValues(m_kParameter.ParameterId, values);
	Close();
end

-- ===========================================================================
function OnItemSelect(item :table, checkBox :table)
	local value = item.Value;
	local selected:boolean = not m_kSelectedValues[value];

	m_kSelectedValues[item.Value] = selected;
	if m_bInvertSelection then
		checkBox:SetCheck(not selected);
	else
		checkBox:SetCheck(selected);
	end

	RefreshCountWarning();
end

-- ===========================================================================
function OnItemFocus(item :table)
	if(item) then
		Controls.FocusedItemName:SetText(item.Name);

		local backColor:number, frontColor:number = UI.GetPlayerColorValues(item.Value, 0);
		local kCityStateData:table = GetCityStateData(item.Value);

		local description:string = Locale.ToUpper("LOC_CITY_STATES_SUZERAIN_BONUSES");

        if kCityStateData ~= nil then
            if kCityStateData.Bonus_XP2 ~= nil and m_RulesetType == XP2_RULESETUP and IsExpansion2Enabled() then
                description = description .. "[NEWLINE]" .. Locale.Lookup(kCityStateData.Bonus_XP2);
            elseif kCityStateData.Bonus_XP1 ~= nil and (m_RulesetType == XP1_RULESETUP or m_RulesetType == XP2_RULESETUP) and IsExpansion1Enabled() then
                description = description .. "[NEWLINE]" .. Locale.Lookup(kCityStateData.Bonus_XP1);
            elseif kCityStateData ~= nil then
                description = description .. "[NEWLINE]" .. Locale.Lookup(kCityStateData.Bonus);
            end
        end

		Controls.FocusedItemDescription:LocalizeAndSetText(description);

		-- Icon
		Controls.FocusedItemIcon:SetIcon(item.Icon);
		Controls.FocusedItemIcon:SetHide(false);
		Controls.FocusedItemIcon:SetColor(frontColor);
	end
end

-- ===========================================================================
function GetCityStateData( civType:string )
	-- Refresh the cache if needed
	if m_kCityStateDataCache[civType] == nil then

		m_kCityStateDataCache[civType] = {};

		local query:string = "SELECT CityStateCategory, Bonus, Bonus_XP1, Bonus_XP2 from CityStates where CivilizationType = ?";
		local kResults:table = DB.ConfigurationQuery(query, civType);
		if(kResults) then
			for i,v in ipairs(kResults) do
				for name, value in pairs(v) do
					m_kCityStateDataCache[civType][name] = value;
				end
			end
		end
	end

	return m_kCityStateDataCache[civType];
end

-- ===========================================================================
function SetAllItems(bState: boolean)
	for _, node in ipairs(m_kItemList) do
		local item:table = node["item"];
		local checkBox:table = node["checkbox"];

		checkBox:SetCheck(bState);
		if m_bInvertSelection then
			m_kSelectedValues[item.Value] = not bState;
		else
			m_kSelectedValues[item.Value] = bState;
		end
	end
end

-- ===========================================================================
function OnSelectAll()
	SetAllItems(true);
	RefreshCountWarning();
end

-- ===========================================================================
function OnSelectNone()
	SetAllItems(false);
	RefreshCountWarning();
end

-- ===========================================================================
function ParameterInitialize(parameter : table, pGameParameters:table)
	m_kParameter = parameter;
	m_kSelectedValues = {};

	m_kCityStateCountParam = pGameParameters.Parameters["CityStateCount"];
	m_OriginalCityStateCount = m_kCityStateCountParam.Value;

	local kRulesetParam = pGameParameters.Parameters["Ruleset"];
	m_RulesetType = kRulesetParam.Value.Value;

	if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
		m_bInvertSelection = true;
	else
		m_bInvertSelection = false;
	end

	if(parameter.Value) then
		for i,v in ipairs(parameter.Value) do
			m_kSelectedValues[v.Value] = true;
		end
	end

	Controls.TopDescription:SetText(parameter.Description);
	Controls.WindowTitle:SetText(parameter.Name);
	m_pItemIM:ResetInstances();

	RefreshList();
	RefreshCountWarning()

	InitCityStateCountSlider(pGameParameters);
	InitSortByFilter();

	OnItemFocus(parameter.Values[1]);
end

-- ===========================================================================
function RefreshList( sortByFunc )

	m_numSelected = 0;
	m_kItemList = {};

	-- Sort list
	table.sort(m_kParameter.Values, sortByFunc ~= nil and sortByFunc or SortByName);

	-- Update UI
	m_pItemIM:ResetInstances();
	for i, v in ipairs(m_kParameter.Values) do
		InitializeItem(v);
	end
end

-- ===========================================================================
function RefreshCountWarning()
	if m_kParameter ~= nil then
		local numSelected:number = 0;

		for i, v in ipairs(m_kParameter.Values) do
			if not IsItemSelected(v) then
				numSelected = numSelected + 1;
			end
		end

		if numSelected < m_kCityStateCountParam.Value then
			Controls.ConfirmButton:SetDisabled(true);
			Controls.CountWarning:SetText(Locale.ToUpper(Locale.Lookup("LOC_CITY_STATE_PICKER_COUNT_WARNING", m_kCityStateCountParam.Value, m_kCityStateCountParam.Value - numSelected)));
		else
			Controls.ConfirmButton:SetDisabled(false);
			Controls.CountWarning:SetText("");
		end
	end
end

-- ===========================================================================
function SortByName(kItemA:table, kItemB:table)
	return Locale.Compare(kItemA.Name, kItemB.Name) == -1;
end

-- ===========================================================================
function SortByType(kItemA:table, kItemB:table)
	local kItemDataA:table = GetCityStateData(kItemA.Value);
	local kItemDataB:table = GetCityStateData(kItemB.Value);

	if kItemDataA.CityStateCategory ~= nil and kItemDataB.CityStateCategory ~= nil then
		return Locale.Compare(kItemDataA.CityStateCategory, kItemDataB.CityStateCategory) == -1;
	else
		return false;
	end
end

-- ===========================================================================
function InitCityStateCountSlider( pGameParameters:table )

	local kValues:table = m_kCityStateCountParam.Values;

	-- ============ CityStateFounder 补丁（本文件唯一的改动）============
	-- 设计：滑条显示的 N = 本局【地图上应该出现】的城邦数；
	--       实际写进参数的是 N + floor(N/2) —— 多出来的那部分
	--       由本模组收走藏起来，供玩家的建邦使者建立。
	--
	-- 配合关系：
	--   · Data/CSF_MapSizes.xml 把引擎上限抬到 X + X/2（X = 官方上限）
	--   · Data/CSF_CityStateCountRange.xml 把滑条【显示】的上限映射回 X
	--   · 这里把玩家选的 N 换算成 N + floor(N/2) 写进参数
	--   · 地图补丁给"超出 CCB 容量"的城邦打 CSF_EXTRA_DORMANT 标记
	--   · CSF_Gameplay.lua 的 -3 模式正好只藏这些标记过的
	--
	-- 反解：已知实际值 A，求显示值 N 使 N + floor(N/2) = A → N ≈ floor(A × 2 / 3)。
	--       用于开局时把默认值还原成显示值（默认 12 → 实际 18）。
	local function CSF_DisplayFromActual(iActual)
		if iActual == nil then return 0 end
		return math.floor(iActual * 2 / 3);
	end
	local function CSF_ActualFromDisplay(iDisplay)
		if iDisplay == nil then return 0 end
		return iDisplay + math.floor(iDisplay / 2);
	end
	-- ============ 补丁结束 ============

	local iDisplay0 = CSF_DisplayFromActual(m_kCityStateCountParam.Value);
	Controls.CityStateCountNumber:SetText(iDisplay0);
	Controls.CityStateCountSlider:SetNumSteps(kValues.MaximumValue - kValues.MinimumValue);
	Controls.CityStateCountSlider:SetStep(iDisplay0 - kValues.MinimumValue);

	Controls.CityStateCountSlider:RegisterSliderCallback(function()
		local stepNum = Controls.CityStateCountSlider:GetStep();
		local iDisplay = m_kCityStateCountParam.Values.MinimumValue + stepNum;
		local iActual = CSF_ActualFromDisplay(iDisplay);

		-- This method can get called pretty frequently, try and throttle it.
		if(m_kCityStateCountParam.Value ~= iActual) then
			pGameParameters:SetParameterValue(m_kCityStateCountParam, iActual);
			-- ★ 显示玩家选的 N，不是实际写入的值
			Controls.CityStateCountNumber:SetText(iDisplay);
			Network.BroadcastGameConfig();
			RefreshCountWarning();
		end
	end);

end

-- ===========================================================================
function InitSortByFilter()

	local uiButton:object = Controls.SortByPulldown:GetButton();
	uiButton:SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_NAME"));

	Controls.SortByPulldown:ClearEntries();

	local pNameEntryInst:object = {};
	Controls.SortByPulldown:BuildEntry( "InstanceOne", pNameEntryInst );
	pNameEntryInst.Button:SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_NAME"));
	pNameEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.SortByPulldown:GetButton():SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_NAME"));
			RefreshList(SortByName);
		end );

	local pTypeEntryInst:object = {};
	Controls.SortByPulldown:BuildEntry( "InstanceOne", pTypeEntryInst );
	pTypeEntryInst.Button:SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_TYPE"));
	pTypeEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.SortByPulldown:GetButton():SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_TYPE"));
			RefreshList(SortByType);
		end );

	Controls.SortByPulldown:CalculateInternals();
end

-- ===========================================================================
function InitializeItem(item:table)
	local c: table = m_pItemIM:GetInstance();
	c.Name:SetText(item.Name);

	local backColor, frontColor = UI.GetPlayerColorValues(item.Value, 0);

	c.Icon:SetIcon(item.Icon);
	c.Icon:SetColor(frontColor);
	c.IconBacking:SetColor(backColor);

	c.Button:RegisterCallback( Mouse.eMouseEnter, function() OnItemFocus(item); end );
	c.Button:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected); end );
	c.Selected:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected); end );
	if m_bInvertSelection then
		c.Selected:SetCheck(not IsItemSelected(item));
	else
		c.Selected:SetCheck(IsItemSelected(item));
		m_numSelected = m_numSelected + 1;
	end

	local listItem:table = {};
	listItem["item"] = item;
	listItem["checkbox"] = c.Selected;
	table.insert(m_kItemList, listItem);
end

-- ===========================================================================
function OnShutdown()
	Close();
	m_pItemIM:DestroyInstances();
	LuaEvents.CityStatePicker_Initialize.Remove( ParameterInitialize );
end

-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local key:number = pInputStruct:GetKey();
		if key == Keys.VK_ESCAPE then
			OnBackButton();
		end
	end
	return true;
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );

	local OnMouseEnter = function() UI.PlaySound("Main_Menu_Mouse_Over"); end;

	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnBackButton );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
	Controls.ConfirmButton:RegisterCallback( Mouse.eLClick, OnConfirmChanges );
	Controls.ConfirmButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
	Controls.SelectAllButton:RegisterCallback( Mouse.eLClick, OnSelectAll);
	Controls.SelectAllButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
	Controls.SelectNoneButton:RegisterCallback( Mouse.eLClick, OnSelectNone);
	Controls.SelectNoneButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);

	LuaEvents.CityStatePicker_Initialize.Add( ParameterInitialize );
end
Initialize();