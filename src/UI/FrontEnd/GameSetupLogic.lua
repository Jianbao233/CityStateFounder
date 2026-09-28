-------------------------------------------------
-- Game Setup Logic
-------------------------------------------------
include( "InstanceManager" );
include ("SetupParameters");

-- ===========================================================================
-- ============ CityStateFounder 补丁 A：数量写入拦截（核心）============
-- ===========================================================================
-- 目的：滑条上显示 / 玩家选的 N = 本局【地图上出现】的城邦数；
--       真正写进游戏配置库的是 N + floor(N/2) —— 多出来的那部分
--       由本模组收走藏起来，供玩家的建邦使者建立。
--
-- ★ 为什么挂在 SetupParameters:SetParameterValue（实测踩了很多轮才定下来）：
--   这是【唯一】真正把参数值写进配置库的地方（SetupParameters.lua:488-493）：
--       function SetupParameters:SetParameterValue(p, v)
--           p.Value = v;
--           self:Config_BeginWrite();
--           self:Config_WriteParameterValues(p);   ← 值在这里落库
--           self:Config_EndWrite(result);
--       end
--
--   之前试过的两个钩子都【改不动落库的值】：
--     · Parameters_Config_EndWrite —— 参数值早在拖滑条时就落库了，
--       此时改内存里的 p.Value 不会回写配置库（实测：日志打了"18 -> 27"，
--       引擎仍只创建 18 个）。
--     · GameParameters_PostProcess —— 同上，而且它只在构建参数时跑一次。
--
--   这里改成【写两次】：先用原值写（p.Value 保持 N，滑条与数字框显示正常），
--   再用放大值直接落库（引擎读到的就是 N + floor(N/2)）。
--
-- 幂等：本函数是"每次设值"的入口，天然每次都会走一遍，不需要额外标记。
local CSF_OrigSetParameterValue = SetupParameters.SetParameterValue;

function SetupParameters:SetParameterValue(p, v)
	-- ① 原样写：保证 p.Value = v，UI（滑条 / 数字框）显示玩家选的值
	local result = CSF_OrigSetParameterValue(self, p, v);

	-- ② 城邦数量：再把放大值写进配置库（UI 不动）
	if p ~= nil and p.ParameterId == "CityStateCount" then
		local iN = tonumber(v);
		if iN ~= nil and iN > 0 then
			local iActual = iN + math.floor(iN / 2);
			local bOK = pcall(function()
				self:Config_Write(p.ConfigurationGroup, p.ConfigurationId, iActual);
			end);
			if bOK then
				pcall(function()
					print("[CSF] 城邦数量：滑条选 " .. tostring(iN) ..
					      " -> 配置库写入 " .. tostring(iActual) ..
					      "（多出的 " .. tostring(iActual - iN) .. " 个由本模组收走供建立）");
				end);
			end
		end
	end

	return result;
end
-- ============ 补丁 A 结束 ============

-- Instance managers for dynamic game options (parent is set dynamically).
g_BooleanParameterManager	= InstanceManager:new("BooleanParameterInstance",	"CheckBox");
g_PullDownParameterManager	= InstanceManager:new("PullDownParameterInstance",	"Root");
g_SliderParameterManager	= InstanceManager:new("SliderParameterInstance",	"Root");
g_StringParameterManager	= InstanceManager:new("StringParameterInstance",	"StringRoot");
g_ButtonParameterManager	= InstanceManager:new("ButtonParameterInstance",	"ButtonRoot");

g_ParameterFactories = {};

-- This is a mapping of instanced controls to their parameters.
-- It's used to cross reference the parameter from the control
-- in order to sort that control.
g_SortingMap = {};

-------------------------------------------------------------------------------
-- Determine which UI stack the parameters should be placed in.
-------------------------------------------------------------------------------
function GetControlStack(group)
	
	local gameModeParametersStack = Controls.GameModeParameterStack;
	if(gameModeParametersStack == nil) then
		gameModeParametersStack = Controls.PrimaryParametersStack;
	end

	local triage = {

		["BasicGameOptions"] = Controls.PrimaryParametersStack,
		["GameOptions"] = Controls.PrimaryParametersStack,
		["BasicMapOptions"] = Controls.PrimaryParametersStack,
		["MapOptions"] = Controls.PrimaryParametersStack,
		["GameModes"] = gameModeParametersStack;
		["Victories"] = Controls.VictoryParameterStack,
		["AdvancedOptions"] = Controls.SecondaryParametersStack,
	};

	-- Triage or default to advanced.
	return triage[group];
end

-------------------------------------------------------------------------------
-- This function wrapper allows us to override this function and prevent
-- network broadcasts for every change made - used currently in Options.lua
-------------------------------------------------------------------------------
function BroadcastGameConfigChanges()
	Network.BroadcastGameConfig();
end

-------------------------------------------------------------------------------
-- Parameter Hooks
-------------------------------------------------------------------------------
-- ===========================================================================
-- ============ CityStateFounder 补丁（本文件唯一的改动）============
-- ===========================================================================
-- 目的：滑条上玩家选 N = 本局【地图上出现】的城邦数；
--       真正写进游戏配置的是 N + floor(N/2) —— 多出来的那部分
--       由本模组收走藏起来，供玩家的建邦使者建立。
--
-- 为什么挂在这里（实测踩了很久才定下来）：
--   · Config_EndWrite 是【把整套配置交给引擎】之前的最后一个钩子，
--     参数里已是玩家选好的值 —— 玩家拖过滑条时靠它。
--     ⚠️ 但它【只在配置被写入时】才跑：游戏会缓存上次的开局设置，
--        直接开局（不动任何设置）就不会写配置 → 钩子根本不跑。
--        （实测：同一份代码，拖过滑条的局 18→27 生效，直接开的局没反应。）
--   · Parameter_PostProcess 在【构建参数】阶段必跑（SetupParameters.lua:1007
--     的 Query Parameters 阶段），而且此时 p.Value 已经是从配置读出来的
--     玩家值（被改的是 p.DefaultValue，不是 p.Value）—— 所以缓存路径靠它。
--   · 前端选择器里的滑条（CityStatePicker.lua）只在点开选择器时才加载，
--     玩家在高级设置界面设数量时它不跑 —— 覆盖它没用。
--
-- 两个钩子都挂上，两条路径就都覆盖了：
--   直接开局（缓存设置） → Parameter_PostProcess
--   拖过滑条            → Config_EndWrite
--
-- 幂等：记下【上一次放大后的值】。若当前值就等于它，说明已经放过了，跳过；
--      若玩家又改了值，则重新放大。这样反复调用 / 反复拖滑条都不会越滚越大。
local CSF_CITYSTATE_LAST_GROWN = "__csfLastGrownValue";

local function CSF_GrowOneParam(p)
	if p == nil or p.Value == nil then return end;

	local iN = tonumber(p.Value);
	if iN == nil or iN <= 0 then return end

	-- 已经放大过（当前值就是上次放大的结果）→ 跳过
	if p[CSF_CITYSTATE_LAST_GROWN] ~= nil and iN == p[CSF_CITYSTATE_LAST_GROWN] then
		return
	end

	local iActual = iN + math.floor(iN / 2);
	p.Value = iActual;
	p[CSF_CITYSTATE_LAST_GROWN] = iActual;

	pcall(function()
		print("[CSF] 城邦数量：滑条选 " .. tostring(iN) ..
		      " -> 实际创建 " .. tostring(iActual) ..
		      "（多出的 " .. tostring(iActual - iN) .. " 个由本模组收走供建立）");
	end);
end

local function CSF_ApplyCityStateGrowth()
	local params = nil;
	pcall(function() params = g_GameParameters and g_GameParameters.Parameters end);
	if params == nil then return end;

	CSF_GrowOneParam(params["CityStateCount"]);
end
-- ============ 补丁结束 ============

function Parameters_Config_EndWrite(o, config_changed)
	SetupParameters.Config_EndWrite(o, config_changed);
	
	-- Dispatch a Lua event notifying that the configuration has changed.
	-- This will eventually be handled by the configuration layer itself.
	if(config_changed) then
		SetupParameters_Log("Marking Configuration as Changed.");
		if(GameSetup_ConfigurationChanged) then
			GameSetup_ConfigurationChanged();
		end
	end
end

function GameParameters_SyncAuxConfigurationValues(o, parameter)
	local result = SetupParameters.Parameter_SyncAuxConfigurationValues(o, parameter);
	
	-- If we don't already need to resync and the parameter is MapSize, perform additional checks.
	if(not result and parameter.ParameterId == "MapSize" and MapSize_ValueNeedsChanging) then
		return MapSize_ValueNeedsChanging(parameter);
	end

	return result;
end

function GameParameters_WriteAuxParameterValues(o, parameter)
	SetupParameters.Config_WriteAuxParameterValues(o, parameter);

	-- Some additional work if the parameter is MapSize.
	if(parameter.ParameterId == "MapSize" and MapSize_ValueChanged) then	
		MapSize_ValueChanged(parameter);
	end
	if(parameter.ParameterId == "Ruleset" and GameSetup_PlayerCountChanged) then
		GameSetup_PlayerCountChanged();
	end
end

-------------------------------------------------------------------------------
-- Hook to determine whether a parameter is relevant to this setup.
-- Parameters not relevant will be completely ignored.
-------------------------------------------------------------------------------
function GetRelevantParameters(o, parameter)

	-- If we have a player id, only care about player parameters.
	if(o.PlayerId ~= nil and parameter.ConfigurationGroup ~= "Player") then
		return false;

	-- If we don't have a player id, ignore any player parameters.
	elseif(o.PlayerId == nil and parameter.ConfigurationGroup == "Player") then
		return false;

	elseif(not GameConfiguration.IsAnyMultiplayer()) then
		return parameter.SupportsSinglePlayer;

	elseif(GameConfiguration.IsHotseat()) then
		return parameter.SupportsHotSeat;

	elseif(GameConfiguration.IsLANMultiplayer()) then
		return parameter.SupportsLANMultiplayer;

	elseif(GameConfiguration.IsInternetMultiplayer()) then
		return parameter.SupportsInternetMultiplayer;

	elseif(GameConfiguration.IsPlayByCloud()) then
		return parameter.SupportsPlayByCloud;
	end
	
	return true;
end


function GameParameters_UI_DefaultCreateParameterDriver(o, parameter, parent)

	if(parent == nil) then
		parent = GetControlStack(parameter.GroupId);
	end

	local control;
	
	-- If there is no parent, don't visualize the control.  This is most likely a player parameter.
	if(parent == nil) then
		return;
	end;

	if(parameter.Domain == "bool") then
		local c = g_BooleanParameterManager:GetInstance();	
		
		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.CheckBox)] = parameter;		
			
		--c.CheckBox:GetTextButton():SetText(parameter.Name);
		c.CheckBox:SetText(parameter.Name);

		
		local tooltip = parameter.Description;
		if(parameter.Invalid) then
			tooltip = string.format("[COLOR_RED]%s[ENDCOLOR][NEWLINE]%s", Locale.Lookup(parameter.InvalidReason), tooltip);
		end

		c.CheckBox:SetToolTipString(tooltip);
		c.CheckBox:RegisterCallback(Mouse.eLClick, function()
			o:SetParameterValue(parameter, not c.CheckBox:IsSelected());
			BroadcastGameConfigChanges();
		end);
		c.CheckBox:ChangeParent(parent);

		control = {
			Control = c,
			UpdateValue = function(value, parameter)
				
				-- Sometimes the parameter name is changed, be sure to update it.
				c.CheckBox:SetText(parameter.Name);

				local tooltip = parameter.Description;
				if(parameter.Invalid) then
					tooltip = string.format("[COLOR_RED]%s[ENDCOLOR][NEWLINE]%s", Locale.Lookup(parameter.InvalidReason), tooltip);
				end

				c.CheckBox:SetToolTipString(tooltip);
				
				-- We have to invalidate the selection state in order
				-- to trick the button to use the right vis state..
				-- Please change this to a real check box in the future...please
				c.CheckBox:SetSelected(not value);
				c.CheckBox:SetSelected(value);
			end,
			SetEnabled = function(enabled)
				c.CheckBox:SetDisabled(not enabled);
			end,
			SetVisible = function(visible)
				c.CheckBox:SetHide(not visible);
			end,
			Destroy = function()
				g_BooleanParameterManager:ReleaseInstance(c);
			end,
		};

	elseif(parameter.Domain == "int" or parameter.Domain == "uint" or parameter.Domain == "text") then
		local c = g_StringParameterManager:GetInstance();		

		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.StringRoot)] = parameter;
				
		c.StringName:SetText(parameter.Name);
		c.StringRoot:SetToolTipString(parameter.Description);
		c.StringEdit:SetEnabled(true);

		local canChangeEnableState = true;

		if(parameter.Domain == "int") then
			c.StringEdit:SetNumberInput(true);
			c.StringEdit:SetMaxCharacters(16);
			c.StringEdit:RegisterCommitCallback(function(textString)
				o:SetParameterValue(parameter, tonumber(textString));	
				BroadcastGameConfigChanges();
			end);
		elseif(parameter.Domain == "uint") then
			c.StringEdit:SetNumberInput(true);
			c.StringEdit:SetMaxCharacters(16);
			c.StringEdit:RegisterCommitCallback(function(textString)
				local value = math.max(tonumber(textString) or 0, 0);
				o:SetParameterValue(parameter, value);	
				BroadcastGameConfigChanges();
			end);
		else
			c.StringEdit:SetNumberInput(false);
			c.StringEdit:SetMaxCharacters(64);
			if UI.HasFeature("TextEntry") == true then
				c.StringEdit:RegisterCommitCallback(function(textString)
					o:SetParameterValue(parameter, textString);	
					BroadcastGameConfigChanges();
				end);
			else
				canChangeEnableState = false;
				c.StringEdit:SetEnabled(false);
			end
		end

		c.StringRoot:ChangeParent(parent);

		control = {
			Control = c,
			UpdateValue = function(value)
				c.StringEdit:SetText(value);
			end,
			SetEnabled = function(enabled)
				if canChangeEnableState then
					c.StringRoot:SetDisabled(not enabled);
					c.StringEdit:SetDisabled(not enabled);
				end
			end,
			SetVisible = function(visible)
				c.StringRoot:SetHide(not visible);
			end,
			Destroy = function()
				g_StringParameterManager:ReleaseInstance(c);
			end,
		};
	elseif (parameter.Values and parameter.Values.Type == "IntRange") then -- Range
		
		local minimumValue = parameter.Values.MinimumValue;
		local maximumValue = parameter.Values.MaximumValue;

		-- Get the UI instance
		local c = g_SliderParameterManager:GetInstance();	

		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Root)] = parameter;

		c.Root:ChangeParent(parent);
		if c.StringName ~= nil then
			c.StringName:SetText(parameter.Name);
		end

		c.OptionTitle:SetText(parameter.Name);
		c.Root:SetToolTipString(parameter.Description);
		c.OptionSlider:RegisterSliderCallback(function()
			local stepNum = c.OptionSlider:GetStep();
			
			-- This method can get called pretty frequently, try and throttle it.
			if(parameter.Value ~= minimumValue + stepNum) then
				o:SetParameterValue(parameter, minimumValue + stepNum);
				BroadcastGameConfigChanges();
			end
		end);


		control = {
			Control = c,
			UpdateValue = function(value)
				if(value) then
					c.OptionSlider:SetStep(value - minimumValue);
					c.NumberDisplay:SetText(tostring(value));
				end
			end,
			UpdateValues = function(values)
				c.OptionSlider:SetNumSteps(values.MaximumValue - values.MinimumValue);
				minimumValue = values.MinimumValue;
				maximumValue = values.MaximumValue;
			end,
			SetEnabled = function(enabled, parameter)
				c.OptionSlider:SetHide(not enabled or parameter.Values == nil or parameter.Values.MinimumValue == parameter.Values.MaximumValue);
			end,
			SetVisible = function(visible, parameter)
				c.Root:SetHide(not visible or parameter.Value == nil );
			end,
			Destroy = function()
				g_SliderParameterManager:ReleaseInstance(c);
			end,
		};	
	elseif (parameter.Values and parameter.Array) then -- MultiValue Array
		
		-- NOTE: This is a limited fall-back implementation of the multi-select parameters.

		-- Get the UI instance
		local c = g_PullDownParameterManager:GetInstance();	

		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Root)] = parameter;

		c.Root:ChangeParent(parent);
		if c.StringName ~= nil then
			c.StringName:SetText(parameter.Name);
		end

		local cache = {};

		control = {
			Control = c,
			Cache = cache,
			UpdateValue = function(value, p)
				local valueText = Locale.Lookup("LOC_SELECTION_NOTHING");
				if(type(value) == "table") then
					local count = #value;
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						if(count == 0) then
							valueText = Locale.Lookup("LOC_SELECTION_EVERYTHING");
						elseif(count == #p.Values) then
							valueText = Locale.Lookup("LOC_SELECTION_NOTHING");
						else
							valueText = Locale.Lookup("LOC_SELECTION_CUSTOM", #p.Values-count);
						end
					else
						if(count == 0) then
							valueText = Locale.Lookup("LOC_SELECTION_NOTHING");
						elseif(count == #p.Values) then
							valueText = Locale.Lookup("LOC_SELECTION_EVERYTHING");
						else
							valueText = Locale.Lookup("LOC_SELECTION_CUSTOM", count);
						end
					end
				end

				if(cache.ValueText ~= valueText) then
					local button = c.PullDown:GetButton();
					button:SetText(valueText);
					cache.ValueText = valueText;
				end
			end,
			UpdateValues = function(values)
				-- Do nothing.
			end,
			SetEnabled = function(enabled, parameter)
				c.PullDown:SetDisabled(true);
			end,
			SetVisible = function(visible)
				c.Root:SetHide(not visible);
			end,
			Destroy = function()
				g_PullDownParameterManager:ReleaseInstance(c);
			end,
		};
	elseif (parameter.Values) then -- MultiValue
		
		-- Get the UI instance
		local c = g_PullDownParameterManager:GetInstance();	

		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Root)] = parameter;

		c.Root:ChangeParent(parent);
		if c.StringName ~= nil then
			c.StringName:SetText(parameter.Name);
		end

		local cache = {};

		control = {
			Control = c,
			Cache = cache,
			UpdateValue = function(value)
				local valueText = value and value.Name or nil;
				local valueDescription = value and value.Description or nil

				-- If value.Description doesn't exist, try value.RawDescription.
				-- This allows dropdowns on Advanced Setup to properly track the user selection.
				if valueDescription == nil and value and value.RawDescription then
					valueDescription = Locale.Lookup(value.RawDescription);
				end

				if(cache.ValueText ~= valueText or cache.ValueDescription ~= valueDescription) then
					local button = c.PullDown:GetButton();
					button:SetText(valueText);
					button:SetToolTipString(valueDescription);
					cache.ValueText = valueText;
					cache.ValueDescription = valueDescription;
				end
			end,
			UpdateValues = function(values)
				local refresh = false;
				local cValues = cache.Values;
				if(cValues and #cValues == #values) then
					for i,v in ipairs(values) do
						local cv = cValues[i];
						if(cv == nil) then
							refresh = true;
							break;
						elseif(cv.QueryId ~= v.QueryId or cv.QueryIndex ~= v.QueryIndex or cv.Invalid ~= v.Invalid or cv.InvalidReason ~= v.InvalidReason) then
							refresh = true;
							break;
						end
					end
				else
					refresh = true;
				end
				
				if(refresh) then
					c.PullDown:ClearEntries();			
					for i,v in ipairs(values) do
						local entry = {};
						c.PullDown:BuildEntry( "InstanceOne", entry );
						entry.Button:SetText(v.Name);
						entry.Button:SetToolTipString(Locale.Lookup(v.RawDescription));

						entry.Button:RegisterCallback(Mouse.eLClick, function()
							o:SetParameterValue(parameter, v);
							BroadcastGameConfigChanges();
						end);
					end
					cache.Values = values;
					c.PullDown:CalculateInternals();
				end
			end,
			SetEnabled = function(enabled, parameter)
				c.PullDown:SetDisabled(not enabled or #parameter.Values <= 1);
			end,
			SetVisible = function(visible)
				c.Root:SetHide(not visible);
			end,
			Destroy = function()
				g_PullDownParameterManager:ReleaseInstance(c);
			end,
		};	
	end

	return control;
end

-- The method used to create a UI control associated with the parameter.
-- Returns either a control or table that will be used in other parameter view related hooks.
function GameParameters_UI_CreateParameter(o, parameter)
	local func = g_ParameterFactories[parameter.ParameterId];

	local control;
	if(func)  then
		control = func(o, parameter);
	else
		control = GameParameters_UI_DefaultCreateParameterDriver(o, parameter);
	end

	o.Controls[parameter.ParameterId] = control;
end


-- Called whenever a parameter is no longer relevant and should be destroyed.
function UI_DestroyParameter(o, parameter)
	local control = o.Controls[parameter.ParameterId];
	if(control) then
		if(control.Destroy) then
			control.Destroy();
		end

		for i,v in ipairs(control) do
			if(v.Destroy) then
				v.Destroy();
			end	
		end
		o.Controls[parameter.ParameterId] = nil;
	end
end

-- Called whenever a parameter's possible values have been updated.
function UI_SetParameterPossibleValues(o, parameter)
	local control = o.Controls[parameter.ParameterId];
	if(control) then
		if(control.UpdateValues) then
			control.UpdateValues(parameter.Values, parameter);
		end

		for i,v in ipairs(control) do
			if(v.UpdateValues) then
				v.UpdateValues(parameter.Values, parameter);
			end	
		end
	end
end

-- Called whenever a parameter's value has been updated.
function UI_SetParameterValue(o, parameter)
	local control = o.Controls[parameter.ParameterId];
	if(control) then
		if(control.UpdateValue) then
			control.UpdateValue(parameter.Value, parameter);
		end

		for i,v in ipairs(control) do
			if(v.UpdateValue) then
				v.UpdateValue(parameter.Value, parameter);
			end	
		end
	end
end

-- Called whenever a parameter is enabled.
function UI_SetParameterEnabled(o, parameter)
	local control = o.Controls[parameter.ParameterId];
	if(control) then
		if(control.SetEnabled) then
			control.SetEnabled(parameter.Enabled, parameter);
		end

		for i,v in ipairs(control) do
			if(v.SetEnabled) then
				v.SetEnabled(parameter.Enabled, parameter);
			end	
		end
	end
end

-- Called whenever a parameter is visible.
function UI_SetParameterVisible(o, parameter)
	local control = o.Controls[parameter.ParameterId];
	if(control) then
		if(control.SetVisible) then
			control.SetVisible(parameter.Visible, parameter);
		end

		for i,v in ipairs(control) do
			if(v.SetVisible) then
				v.SetVisible(parameter.Visible, parameter);
			end	
		end
	end
end

-------------------------------------------------------------------------------
-- Called after a refresh was performed.
-- Update all of the game option stacks and scroll panels.
-------------------------------------------------------------------------------
function GameParameters_UI_AfterRefresh(o)

	-- All parameters are provided with a sort index and are manipulated
	-- in that particular order.
	-- However, destroying and re-creating parameters can get expensive
	-- and thus is avoided.  Because of this, some parameters may be 
	-- created in a bad order.  
	-- It is up to this function to ensure order is maintained as well
	-- as refresh/resize any containers.
	-- FYI: Because of the way we're sorting, we need to delete instances
	-- rather than release them.  This is because releasing merely hides it
	-- but it still gets thrown in for sorting, which is frustrating.
	local sort = function(a,b)
	
		-- ForgUI requires a strict weak ordering sort.

		local ap = g_SortingMap[tostring(a)];
		local bp = g_SortingMap[tostring(b)];

		if(ap == nil and bp ~= nil) then
			return true;
		elseif(ap == nil and bp == nil) then
			return tostring(a) < tostring(b);
		elseif(ap ~= nil and bp == nil) then
			return false;
		else
			return o.Utility_SortFunction(ap, bp);
		end
	end

	local stacks = {	
		{Controls.PrimaryParametersStack},
		{Controls.SecondaryParametersStack,Controls.SecondaryParametersHeader},
		{Controls.GameModeParameterStack,Controls.GameModeParametersHeader},
		{Controls.VictoryParameterStack,Controls.VictoryParametersHeader}
	};

	for i,v in ipairs(stacks) do
		local s = v[1];
		local h = v[2];
		if(s) then
			local children = s:GetChildren();
		
			local hide = true;
			for _,c in ipairs(children) do
				if(c:IsVisible()) then
					hide = false;			
					break;
				end
			end

			if(h) then
				h:SetHide(hide);
			end

			s:SetHide(hide);
		end
	end

	for i,v in ipairs(stacks) do
		local s = v[1];
		if(s and s:IsVisible()) then
			s:SortChildren(sort);
		end
	end

	for i,v in ipairs(stacks) do
		local s = v[1];
		if(s) then
			s:CalculateSize();
			s:ReprocessAnchoring();
		end
	end
	   
	Controls.ParametersStack:CalculateSize();
	Controls.ParametersStack:ReprocessAnchoring();

	if Controls.ParametersScrollPanel then
		Controls.ParametersScrollPanel:CalculateInternalSize();
	end
end

-------------------------------------------------------------------------------
-- Perform any additional operations on relevant parameters.
-- In this case, adjust the parameter group so that they are sorted properly.
-------------------------------------------------------------------------------
function GameParameters_PostProcess(o, parameter)
	
	-- Move all groups into 1 singular group for sorting purposes.
	--local triage = {
		--["BasicGameOptions"] = "GameOptions",
		--["BasicMapOptions"] = "GameOptions",
		--["MapOptions"] = "GameOptions",
	--};
--
	--parameter.GroupId = triage[parameter.GroupId] or parameter.GroupId;

end

-- Generate the game setup parameters and populate the UI.
function BuildGameSetup(createParameterFunc)

	-- If BuildGameSetup is called twice, call HideGameSetup to reset things.
	if(g_GameParameters) then
		HideGameSetup();
	end

	print("Building Game Setup");

	g_GameParameters = SetupParameters.new();
	g_GameParameters.Config_EndWrite = Parameters_Config_EndWrite;
	g_GameParameters.Parameter_GetRelevant = GetRelevantParameters;
	g_GameParameters.Parameter_PostProcess = GameParameters_PostProcess;
	g_GameParameters.Parameter_SyncAuxConfigurationValues = GameParameters_SyncAuxConfigurationValues;
	g_GameParameters.Config_WriteAuxParameterValues = GameParameters_WriteAuxParameterValues;
	g_GameParameters.UI_BeforeRefresh = UI_BeforeRefresh;
	g_GameParameters.UI_AfterRefresh = GameParameters_UI_AfterRefresh;
	g_GameParameters.UI_CreateParameter = createParameterFunc ~= nil and createParameterFunc or GameParameters_UI_CreateParameter;
	g_GameParameters.UI_DestroyParameter = UI_DestroyParameter;
	g_GameParameters.UI_SetParameterPossibleValues = UI_SetParameterPossibleValues;
	g_GameParameters.UI_SetParameterValue = UI_SetParameterValue;
	g_GameParameters.UI_SetParameterEnabled = UI_SetParameterEnabled;
	g_GameParameters.UI_SetParameterVisible = UI_SetParameterVisible;

	-- Optional overrides.
	if(GameParameters_FilterValues) then
		g_GameParameters.Default_Parameter_FilterValues = g_GameParameters.Parameter_FilterValues;
		g_GameParameters.Parameter_FilterValues = GameParameters_FilterValues;
	end

	g_GameParameters:Initialize();
	g_GameParameters:FullRefresh();
end

-- Generate the game setup parameters and populate the UI.
function BuildHeadlessGameSetup()

	-- If BuildGameSetup is called twice, call HideGameSetup to reset things.
	if(g_GameParameters) then
		HideGameSetup();
	end

	print("Building Headless Game Setup");

	g_GameParameters = SetupParameters.new();
	g_GameParameters.Config_EndWrite = Parameters_Config_EndWrite;
	g_GameParameters.Parameter_GetRelevant = GetRelevantParameters;
	g_GameParameters.Parameter_PostProcess = GameParameters_PostProcess;
	g_GameParameters.Parameter_SyncAuxConfigurationValues = GameParameters_SyncAuxConfigurationValues;
	g_GameParameters.Config_WriteAuxParameterValues = GameParameters_WriteAuxParameterValues;

	g_GameParameters.UpdateVisualization = function() end
	g_GameParameters.UI_AfterRefresh = nil;
	g_GameParameters.UI_CreateParameter = nil;
	g_GameParameters.UI_DestroyParameter = nil;
	g_GameParameters.UI_SetParameterPossibleValues = nil;
	g_GameParameters.UI_SetParameterValue = nil;
	g_GameParameters.UI_SetParameterEnabled = nil;
	g_GameParameters.UI_SetParameterVisible = nil;

	-- Optional overrides.
	if(GameParameters_FilterValues) then
		g_GameParameters.Default_Parameter_FilterValues = g_GameParameters.Parameter_FilterValues;
		g_GameParameters.Parameter_FilterValues = GameParameters_FilterValues;
	end

	g_GameParameters:Initialize();
end

-- ===========================================================================
-- Hide game setup parameters.
function HideGameSetup(hideParameterFunc)
	print("Hiding Game Setup");

	-- Shutdown and nil out the game parameters.
	if(g_GameParameters) then
		g_GameParameters:Shutdown();
		g_GameParameters = nil;
	end

	-- Reset all UI instances.
	if(hideParameterFunc == nil) then
		g_BooleanParameterManager:ResetInstances();
		g_PullDownParameterManager:ResetInstances();
		g_SliderParameterManager:ResetInstances();
		g_StringParameterManager:ResetInstances();
		g_ButtonParameterManager:ResetInstances();
	else
		hideParameterFunc();
	end
end

-- ===========================================================================
function MapSize_ValueNeedsChanging(p)
	local results = CachedQuery("SELECT * from MapSizes where Domain = ? and MapSizeType = ? LIMIT 1", p.Value.Domain, p.Value.Value);

	local minPlayers = 2;
	local maxPlayers = 2;
	local defPlayers = 2;
	local minCityStates = 0;
	local maxCityStates = 0;
	local defCityStates = 0;

	if(results) then
		for i, v in ipairs(results) do
			minPlayers = v.MinPlayers;
			maxPlayers = v.MaxPlayers;
			defPlayers = v.DefaultPlayers;
			minCityStates = v.MinCityStates;
			maxCityStates = v.MaxCityStates;
			defCityStates = v.DefaultCityStates;
		end
	end

	-- TODO: Add Min/Max city states, set defaults.
	if(MapConfiguration.GetMinMajorPlayers() ~= minPlayers) then
		SetupParameters_Log("Min Major Players: " .. MapConfiguration.GetMinMajorPlayers() .. " should be " .. minPlayers);
		return true;
	elseif(MapConfiguration.GetMaxMajorPlayers() ~= maxPlayers) then
		SetupParameters_Log("Max Major Players: " .. MapConfiguration.GetMaxMajorPlayers() .. " should be " .. maxPlayers);
		return true;
	elseif(MapConfiguration.GetMinMinorPlayers() ~= minCityStates) then
		SetupParameters_Log("Min Minor Players: " .. MapConfiguration.GetMinMinorPlayers() .. " should be " .. minCityStates);
		return true;
	elseif(MapConfiguration.GetMaxMinorPlayers() ~= maxCityStates) then
		SetupParameters_Log("Max Minor Players: " .. MapConfiguration.GetMaxMinorPlayers() .. " should be " .. maxCityStates);
		return true;
	end

	return false;
end

function MapSize_ValueChanged(p)
	SetupParameters_Log("MAP SIZE CHANGED");

	-- The map size has changed!
	-- Adjust the number of players to match the default players of the map size.
	local results = CachedQuery("SELECT * from MapSizes where Domain = ? and MapSizeType = ? LIMIT 1", p.Value.Domain, p.Value.Value);

	local minPlayers = 2;
	local maxPlayers = 2;
	local defPlayers = 2;
	local minCityStates = 0;
	local maxCityStates = 0;
	local defCityStates = 0;

	if(results) then
		for i, v in ipairs(results) do
			minPlayers = v.MinPlayers;
			maxPlayers = v.MaxPlayers;
			defPlayers = v.DefaultPlayers;
			minCityStates = v.MinCityStates;
			maxCityStates = v.MaxCityStates;
			defCityStates = v.DefaultCityStates;
		end
	end

	MapConfiguration.SetMinMajorPlayers(minPlayers);
	MapConfiguration.SetMaxMajorPlayers(maxPlayers);
	MapConfiguration.SetMinMinorPlayers(minCityStates);
	MapConfiguration.SetMaxMinorPlayers(maxCityStates);
	GameConfiguration.SetValue("CITY_STATE_COUNT", defCityStates);

	-- Clamp participating player count in network multiplayer so we only ever auto-spawn players up to the supported limit. 
	local mpMaxSupportedPlayers = 8; -- The officially supported number of players in network multiplayer games.
	local participatingCount = defPlayers + GameConfiguration.GetHiddenPlayerCount();
	if GameConfiguration.IsNetworkMultiplayer() or GameConfiguration.IsPlayByCloud() then
		participatingCount = math.clamp(participatingCount, 0, mpMaxSupportedPlayers);
	end

	SetupParameters_Log("Setting participating player count to " .. tonumber(participatingCount));
	local playerCountChange = GameConfiguration.SetParticipatingPlayerCount(participatingCount);
	Network.BroadcastGameConfig(true);


	-- NOTE: This used to only be called if playerCountChange was non-zero.
	-- This needs to be called more frequently than that because each player slot entry's add/remove button
	-- needs to be potentially updated to reflect the min/max player constraints.
	if(GameSetup_PlayerCountChanged) then
		GameSetup_PlayerCountChanged();
	end
end

function GetGameModeInfo(gameModeType)
	local item_query : string = "SELECT * FROM GameModeItems where GameModeType = ? ORDER BY SortIndex";
	local item_results : table = CachedQuery(item_query, gameModeType);

	return item_results[1];
end
