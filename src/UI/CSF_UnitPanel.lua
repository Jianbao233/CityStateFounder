-- ===========================================================================
-- CityStateFounder / 城邦缔造者 — UnitPanel 补丁（InGame 上下文）
-- 区段：InGameActions > ReplaceUIScript（LuaContext=UnitPanel）+ ImportFiles
--
-- 官方范式（DLC/Expansion2/UI/Replacements/UnitPanel_Expansion1.lua）：
--     整个替换文件只有一行 include("UnitPanel");
-- 即：先加载原生，再在全局作用域里覆盖/追加。
--
-- 为什么必须走 ReplaceUIScript：
--     官方 MODDING 钩子 LateCheckActionBeforeAdd / LateCheckOperationBeforeAdd
--     （UnitPanel.lua:364-373）【只能改既有动作的图标/tooltip/禁用，不能凭空新增动作】。
--     而 UNIT_CSF_ENVOY 的 FoundCity=0，引擎根本不会给它 FOUND_CITY 动作。
--
-- 注入点选择：
--     覆盖全局函数 GetUnitActionsTable(pUnit)（UnitPanel.lua:379）
--     —— 它是动作列表的构建入口，先调原生再追加，最干净、不会重复注入。
--     （对比：LateCheckActionBeforeAdd 是按动作逐个调用的，在里面追加会重复。）
--
-- 依赖：AddActionToTable 是全局函数（UnitPanel.lua:271），可直接调用。
--       它要求 action 表至少有 CategoryInUI / Icon 两个字段。
-- ===========================================================================

include("UnitPanel");

print("[CSF] CSF_UnitPanel.lua loading (UnitPanel replacement)");

-- 自定义动作标识（userTag），避免与引擎的 UnitOperationTypes 冲突
local CSF_ACTION_HASH = 0x43534601;

-- 保存原生实现
local BASE_GetUnitActionsTable = GetUnitActionsTable;

-- ---------------------------------------------------------------------------
-- 覆盖：构建动作列表
-- ---------------------------------------------------------------------------
function GetUnitActionsTable(pUnit)
    local tActions = BASE_GetUnitActionsTable(pUnit);

    if pUnit == nil or tActions == nil then
        return tActions;
    end

    -- 只对「建邦使节」追加动作
    local sUnitType = nil;
    pcall(function()
        sUnitType = GameInfo.Units[pUnit:GetType()].UnitType;
    end);

    if sUnitType == "UNIT_CSF_ENVOY" then
        local kAction = {
            CategoryInUI      = "SPECIFIC",                            -- 次要动作区
            Icon              = "ICON_UNITOPERATION_FOUND_CITY",       -- 复用开拓者的建城图标
            IsBestImprovement = false,
            Sound             = "Click_Confirm",
        };

        AddActionToTable(
            tActions,
            kAction,
            false,
            Locale.Lookup("LOC_CSF_ACTION_FOUND_CITY_STATE_TT"),
            CSF_ACTION_HASH,
            function()
                -- ⚠️ 关键：不能把 pUnit 跨 context 传！
                --    Civ6 每个 UI context 有【独立的 Lua state】，
                --    userdata（单位对象）传过去会失效 → 对方拿到 nil → 静默无反应。
                --    只传【纯数字】：坐标 + 单位 ID + 拥有者 ID。
                --    有了后两者，GameCore 侧就能用 UnitManager.GetUnit(owner, id)
                --    精确定位并删除这个单位（建邦后消耗掉）。
                local iX     = pUnit:GetX();
                local iY     = pUnit:GetY();
                local iUnit  = pUnit:GetID();
                local iOwner = pUnit:GetOwner();
                print("[CSF] action clicked; unit id=" .. tostring(iUnit) ..
                      " owner=" .. tostring(iOwner) ..
                      " at (" .. tostring(iX) .. "," .. tostring(iY) .. ") -> raise CSF_OpenPanel");
                LuaEvents.CSF_OpenPanel(iX, iY, iUnit, iOwner);
            end
        );

        print("[CSF] injected 'Found City-State' action for unit " .. tostring(pUnit:GetID()));
    end

    return tActions;
end

print("[CSF] CSF_UnitPanel.lua ready (GetUnitActionsTable overridden)");
