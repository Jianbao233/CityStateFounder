--------------------------------------------------------------------------------
-- test_csf_safety_harness.lua
--
-- 【真实 Lua 运行时夹具】—— 不是字符串断言。
--
--   做法：在受控桩环境（Players / Map / UnitManager / C6FW / WorldBuilder …）
--         里 `dofile` 真正被测试的两个脚本：
--             src/Lua/CSF_CreateCityState.lua
--             src/Lua/CSF_Gameplay.lua
--         然后直接调用它们【真实】的函数（ExposedMembers.CSF.*），
--         观察返回码、引擎调用次数、存档属性、UI 广播。
--
--   运行方式（由 tools/test_csf_safety.py 驱动）：
--             lua -> dofile(this)，并预先设好全局 CSF_SRC_DIR
--
--   输出格式（供 Python 解析）：
--       RESULT|<用例名>|PASS 或 FAIL|<细节>
--       TOTAL|<用例数>
--       FAILED|<失败数>
--------------------------------------------------------------------------------

local SRC = assert(CSF_SRC_DIR, "CSF_SRC_DIR 未设置（应由 test_csf_safety.py 注入）");
local F_GAMEPLAY = CSF_LUA_GAMEPLAY or (SRC .. "/Lua/CSF_Gameplay.lua");
local F_CREATE   = CSF_LUA_CREATE   or (SRC .. "/Lua/CSF_CreateCityState.lua");

-- 前置：被测文件必须真实存在（夹具本身在 tools/ 下，不会被 mod 加载，用 io 无副作用）
do
    local a = assert(io.open(F_GAMEPLAY, "r"), "打不开被测文件：" .. F_GAMEPLAY);
    a:close();
    local b = assert(io.open(F_CREATE, "r"), "打不开被测文件：" .. F_CREATE);
    b:close();
end

local real_print = print;
local RESULTS = {};
local LOG = {};

local function log_clear() LOG = {} end
local function log_text() return table.concat(LOG, "\n") end
local function log_has(s) return log_text():find(s, 1, true) ~= nil end

local function check(name, cond, detail)
    RESULTS[#RESULTS + 1] = {
        name = name,
        ok = (cond == true),
        detail = tostring(detail),
    };
end

local function check_eq(name, got, want)
    check(name, got == want, "got=" .. tostring(got) .. " want=" .. tostring(want));
end

--------------------------------------------------------------------------------
-- 受控世界（桩状态）
--------------------------------------------------------------------------------
local W = {};
local TARGET_CIV = "CIVILIZATION_ANTANANARIVO";
local OTHER_CIV  = "CIVILIZATION_ZANZIBAR";
local TARGET_SLOT = 41;
local TARGET_SLOT2 = 42;

local function key2(x, y) return tostring(x) .. "," .. tostring(y) end

local function new_world()
    W = {
        gw = 20, gh = 20,
        turn = 10,
        players = {},          -- id -> player 对象
        cfgs = {},             -- id -> PlayerConfiguration 对象
        cities = {},           -- 全局城市列表
        units = {},            -- 全局单位列表
        plot_owner = {},       -- "x,y" -> owner（缺省 = -1 无主）
        plot_water = {},
        plot_mountain = {},
        plot_feature = {},
        props = {},            -- Game:SetProperty 存档属性
        broadcast = {},        -- GameEvents.CSF_FoundResult 广播
        alive_minors = {},
        alive_majors = { 0 },
        create_behavior = "ok",   -- ok | throw | silent | count_only
        activate_ret = 1,
        activate_partial = false,  -- true = 原生桥"改了一部分状态"后仍返回失败
        activate_publishes_alive = false, -- 新版 ActivatePlayer 已完成官方 alive 发布
        snapshot_mode = nil,       -- nil/good = 原生 good 快照；bad = 坏列表
        native_status_mode = nil,  -- nil = 旧桥；good / bad = 原生槽位状态导出
        turn_tasks = {},           -- slot -> {a,b,c}：目标玩家回合任务三向量
        turn_task_caps = {},       -- slot -> {a,b,c}：容量；缺省 256/256/256
        turn_task_read = true,     -- false = 目标任务读不到
        turn_task_owner_matches = true, -- false = 原生 owner 不匹配
        init_tasks_behavior = "ok",-- ok | silent | partial | throw | throw_after
        set_alive_ret = 1,
        color_mode = "ok",         -- ok | ok_false（返回布尔 false）| 其它（返回 nil）
        status_set_effective = true,   -- false = 模拟引擎拒绝改槽位状态（仍是 5）
        status_get_nil = false,        -- true = pm:GetSlotStatus 读不到（nil）
        on_create = nil,
        calls = {
            create = {}, init_unit = {}, kill = 0, add_player = 0, uninit = {},
            activate = 0, set_alive = 0, consume = 0, init_turn_tasks = 0,
        },
        native_activated = {},
        contacts = {}, tokens = {}, stock = {}, reward_calls = 0, combat = {},
        contact_silent = false, reward_silent = false, reward_throw_after = false,
        next_uid = 1000,
    };
end

local function make_city(owner, x, y)
    local c = { _owner = owner, _x = x, _y = y, _name = "LOC_CITY_NAME_FALLBACK" };
    function c:GetID() return 65536 end
    function c:GetName() return self._name end
    function c:SetName(name)
        W.copy_name_calls = (W.copy_name_calls or 0) + 1;
        if W.copy_name_behavior == "throw" then error("name setter failed"); end
        if W.copy_name_behavior == "silent" then return; end
        self._name = name;
        if W.copy_name_behavior == "throw_after" then error("name changed before error"); end
    end
    function c:GetOwner() return self._owner end
    function c:GetX() return self._x end
    function c:GetY() return self._y end
    function c:GetDistricts()
        return {GetDistrictAtLocation = function()
            return {GetDefenseStrength = function() return (W.combat[owner] or 0) - 2; end};
        end};
    end
    return c;
end

local function live_cities(owner)
    local t = {};
    for _, c in ipairs(W.cities) do
        if c._owner == owner then t[#t + 1] = c end
    end
    return t;
end

local function live_units(owner)
    local t = {};
    for _, u in ipairs(W.units) do
        if u._owner == owner and not u._dead then t[#t + 1] = u end
    end
    return t;
end

local function add_unit(owner, sType, x, y)
    W.next_uid = W.next_uid + 1;
    local u = {
        _id = W.next_uid, _owner = owner, _type = sType, _x = x, _y = y, _dead = false,
    };
    function u:GetID() return self._id end
    function u:GetOwner() return self._owner end
    function u:GetX() return self._x end
    function u:GetY() return self._y end
    function u:GetType() return self._type end
    W.units[#W.units + 1] = u;
    return u;
end

local function make_player(id, alive)
    local P = { _id = id, _alive = (alive == true) };
    function P:IsAlive() return self._alive end
    function P:GetStats()
        return {UpdateMaxMeleeStrengthTrained = function(_, value)
            if not W.defense_silent then W.combat[id] = math.max(W.combat[id] or 0, value); end
        end};
    end
    function P:GetDiplomacy()
        return {
            HasMet = function(_, other) return W.contacts[key2(id, other)] == true; end,
            SetHasMet = function(_, other)
                if not W.contact_silent then
                    if W.contact_reward and not W.contacts[key2(id, other)] and id == 0 then
                        local k = key2(other, id); W.tokens[k] = (W.tokens[k] or 0) + 1;
                    end
                    W.contacts[key2(id, other)] = true;
                    W.contacts[key2(other, id)] = true;
                end
            end,
        };
    end
    function P:GetInfluence()
        return {
            CanReceiveInfluence = function() return id ~= 0; end,
            GetTokensReceived = function(_, other) return W.tokens[key2(id, other)] or 0; end,
            GetTokensToGive = function() return W.stock[id] or 0; end,
            GiveFreeTokenToPlayer = function(_, other)
                W.reward_calls = W.reward_calls + 1;
                if not W.reward_silent then
                    local k = key2(other, id); W.tokens[k] = (W.tokens[k] or 0) + 1;
                end
                if W.reward_throw_after then error("effect happened before error"); end
            end,
        };
    end
    function P:GetCities()
        local c = {};
        function c:GetCount() return #live_cities(P._id) end
        function c:Members() return ipairs(live_cities(P._id)) end
        function c:Create(x, y)
            W.calls.create[#W.calls.create + 1] = { player = P._id, x = x, y = y };
            if W.create_behavior == "throw" then
                error("stub: Cities:Create threw");
            end
            if W.create_behavior == "silent" then
                -- 引擎"报了 OK 但城市列表没变"（实测的静默失败）
                if W.on_create ~= nil then W.on_create(P._id, x, y) end
                return;
            end
            if W.create_behavior == "count_only" then
                -- 城市数变了，但【不在目标格】—— 模拟"别处有城、目标格没有"
                W.cities[#W.cities + 1] = make_city(P._id, 0, 0);
                if W.on_create ~= nil then W.on_create(P._id, x, y) end
                return;
            end
            W.cities[#W.cities + 1] = make_city(P._id, x, y);
            if W.on_create ~= nil then W.on_create(P._id, x, y) end
        end
        return c;
    end
    function P:GetUnits()
        local c = {};
        function c:GetCount() return #live_units(P._id) end
        function c:Members() return ipairs(live_units(P._id)) end
        return c;
    end
    return P;
end

local function make_cfg(opt)
    local C = {
        _civ = opt.civ, _leader = opt.leader,
        _level = opt.level or "CIVILIZATION_LEVEL_CITY_STATE",
        _status = opt.status or 5,
        _color = opt.color,
        _alive = false,
    };
    function C:GetCivilizationTypeName() return self._civ end
    function C:GetLeaderTypeName() return self._leader end
    function C:GetCivilizationLevelTypeName() return self._level end
    function C:GetSlotStatus() return self._status end
    function C:GetColor() return self._color end
    function C:GetCivilizationShortDescription() return self._short end
    function C:GetCivilizationDescription() return self._description end
    return C;
end

local function make_plot(x, y)
    local k = key2(x, y);
    local p = { _x = x, _y = y };
    function p:GetOwner()
        local o = W.plot_owner[k];
        if o == nil then return -1 end
        return o;
    end
    function p:SetOwner(o) W.plot_owner[k] = o end
    function p:IsWater() return W.plot_water[k] == true end
    function p:IsMountain() return W.plot_mountain[k] == true end
    function p:GetFeatureType()
        local f = W.plot_feature[k];
        if f == nil then return -1 end
        return f;
    end
    function p:GetX() return x end
    function p:GetY() return y end
    return p;
end

-- ------------------------------------------------------------------ 桩环境装填
local HOOKS = { lsc = nil, uam = nil, gce = nil };

local function install_env()
    Players = setmetatable({}, { __index = function(_, k) return W.players[k] end });
    PlayerConfigurations = setmetatable({}, { __index = function(_, k) return W.cfgs[k] end });

    Map = {
        GetPlot = function(x, y)
            if x == nil or y == nil then return nil end
            if x < 0 or y < 0 or x >= W.gw or y >= W.gh then return nil end
            return make_plot(x, y);
        end,
        GetGridSize = function() return W.gw, W.gh end,
        GetPlotDistance = function(x1, y1, x2, y2)
            return math.max(math.abs(x1 - x2), math.abs(y1 - y2));
        end,
    };

    Cities = {
        GetCityInPlot = function(x, y)
            for _, c in ipairs(W.cities) do
                if c._x == x and c._y == y then return c end
            end
            return nil;
        end,
    };

    PlayerManager = {
        GetAliveMinorIDs = function() return W.alive_minors end,
        GetAliveMajorIDs = function() return W.alive_majors end,
    };

    UnitManager = {
        GetUnit = function(owner, id)
            for _, u in ipairs(W.units) do
                if u._owner == owner and u._id == id and not u._dead then return u end
            end
            return nil;
        end,
        Kill = function(u, b)
            W.calls.kill = W.calls.kill + 1;
            if u ~= nil then u._dead = true end
            return true;
        end,
        InitUnit = function(owner, sType, x, y)
            W.calls.init_unit[#W.calls.init_unit + 1] =
                { owner = owner, unit_type = sType, x = x, y = y };
            return add_unit(owner, sType, x, y);
        end,
    };

    -- 注意：引擎的 Game:GetProperty / Game:SetProperty 是【冒号】方法，
    --       而 Game.GetCurrentGameTurn / Game.GetLocalPlayer 是【点】调用。
    --       这里把属性访问器写成两种写法都接受，避免夹具自身把键写错。
    Game = {
        GetCurrentGameTurn = function() return W.turn end,
        GetLocalPlayer = function() return 0 end,
        GetProperty = function(a, b)
            local k = b;
            if k == nil then k = a end
            return W.props[k];
        end,
        SetProperty = function(a, b, c)
            local k, v = a, b;
            if a == Game then k, v = b, c end
            W.props[k] = v;
        end,
    };

    GameConfiguration = {
        GetValue = function(_) return "RULESET_EXPANSION_2" end,
        SetValue = function(_, _) return true end,
    };

    GameInfo = {
        Civilizations = setmetatable({
            [TARGET_CIV]={CivilizationType=TARGET_CIV,StartingCivilizationLevelType="CIVILIZATION_LEVEL_CITY_STATE",Name="LOC_TARGET_NAME",Description="LOC_TARGET_DESCRIPTION",Adjective="LOC_TARGET_ADJECTIVE"},
            [OTHER_CIV]={CivilizationType=OTHER_CIV,StartingCivilizationLevelType="CIVILIZATION_LEVEL_CITY_STATE",Name="LOC_OTHER_NAME",Description="LOC_OTHER_DESCRIPTION",Adjective="LOC_OTHER_ADJECTIVE"},
            CIVILIZATION_ROME={CivilizationType="CIVILIZATION_ROME",StartingCivilizationLevelType="CIVILIZATION_LEVEL_FULL_CIV"},
        }, {__call=function(t)
            local k; return function() k=next(t,k); if k then return t[k] end end;
        end}),
        CivilizationLeaders = function()
            local rows={
                { CivilizationType = TARGET_CIV, LeaderType = "LEADER_MINOR_CIV_ANTANANARIVO" },
                { CivilizationType = OTHER_CIV,  LeaderType = "LEADER_MINOR_CIV_ZANZIBAR" },
            };
            local i=0;return function()i=i+1;return rows[i]end;
        end,
        Leaders = { LEADER_MINOR_CIV_ANTANANARIVO = {InheritFrom="LEADER_DEFAULT"},
                    LEADER_MINOR_CIV_ZANZIBAR = {}, LEADER_DEFAULT={} },
        LeaderTraits = function()
            local rows={{LeaderType="LEADER_MINOR_CIV_ANTANANARIVO",TraitType="TARGET_TRAIT"},
                {LeaderType="LEADER_DEFAULT",TraitType="DEFAULT_TRAIT"},
                {LeaderType="LEADER_MINOR_CIV_ZANZIBAR",TraitType="OTHER_TRAIT"}};
            local i=0;return function()i=i+1;return rows[i]end;
        end,
        CivilizationTraits = function() return function()return nil end; end,
        TraitModifiers = function()
            local rows={{TraitType="TARGET_TRAIT",ModifierId="TARGET_ABILITY"},
                {TraitType="TARGET_TRAIT",ModifierId="TARGET_SECOND"},
                {TraitType="DEFAULT_TRAIT",ModifierId="DEFAULT_ABILITY"},
                {TraitType="OTHER_TRAIT",ModifierId="OTHER_ABILITY"}};
            local i=0;return function()i=i+1;return rows[i]end;
        end,
        CityNames = function()
            local rows = W.no_city_names and {} or {
                {CivilizationType=TARGET_CIV,CityName="LOC_CITY_NAME_TARGET"},
                {CivilizationType=OTHER_CIV,CityName="LOC_CITY_NAME_OTHER"},
            };
            local i=0;return function()i=i+1;return rows[i]end;
        end,
        Features = {},
        Units = { [0] = { UnitType = "UNIT_CSF_ENVOY" }, [1] = { UnitType = "UNIT_SETTLER" },
                  UNIT_WARRIOR = {Combat = 20} },
    };

    DB = {
        ConfigurationQuery = function(_) return {} end,
    };

    GameEvents = {
        CSF_FoundRequest = {Add=function(f) W.operation=f end},
        CSF_FoundResult = function(ok, reason, player, x, y)
            W.broadcast[#W.broadcast + 1] =
                { ok = ok, reason = reason, player = player, x = x, y = y };
        end,
    };

    HOOKS = { lsc = nil, uam = nil, gce = nil };
    Events = {
        LoadScreenClose = { Add = function(f) HOOKS.lsc = f end },
        UnitAddedToMap = { Add = function(f) HOOKS.uam = f end },
        GameCoreEventPublishComplete = { Add = function(f) HOOKS.gce = f end },
    };

    -- WorldBuilder.PlayerManager()
    local pm = {};
    function pm:GetSlotStatus(i)
        -- status_get_nil = true → 模拟"读不到状态证据"（必须判失败，不能当 OK）
        if W.status_get_nil == true then return nil end
        local c = W.cfgs[i];
        if c == nil then return 5 end
        return c._status;
    end
    function pm:SetPlayerSlotStatus(i, s)
        local c = W.cfgs[i];
        if c == nil then return end
        -- status_set_effective = false 时模拟"引擎拒绝改槽位状态"
        -- （逆向依据：预注册态 5 会被 FUN_180617370 的状态门禁静默拒绝）
        if W.status_set_effective == false then return end
        c._status = s;
    end
    function pm:AddPlayer(_b)
        W.calls.add_player = W.calls.add_player + 1;
        return nil;                      -- 默认：没有空槽（dynamic 兜底关着，走不到）
    end
    function pm:UninitializePlayer(i)
        W.calls.uninit[#W.calls.uninit + 1] = i;
        W.players[i] = nil;
        W.cfgs[i] = nil;
    end
    function pm:SetPlayerLeader(_i, _leader, _civ, _level) return true end
    function pm:SetRandomMinorStartingPosition(_i) return true end
    WorldBuilder = {
        PlayerManager = function() return pm end,
    };

    W.modifiers=W.modifiers or {};
    GameEffects={
        GetModifiers=function()local ids={};for i in ipairs(W.modifiers)do ids[#ids+1]=i end;return ids end,
        GetModifierOwner=function(id)return W.modifiers[id].slot end,
        GetObjectType=function()return "LOC_MODIFIER_OBJECT_PLAYER"end,
        GetObjectsPlayerId=function(owner)return owner end,
        GetModifierDefinition=function(id)return {Id=W.modifiers[id].name}end,
    };
    -- C6FW 原生桥（契约：成功 = 1，失败 = 0 / nil）
    C6FW = {
        PublishCityStateReady=function(slot)
            W.publish_ready_calls=(W.publish_ready_calls or 0)+1;
            if not W.ability_silent then
                for _,name in ipairs({"TARGET_ABILITY","TARGET_SECOND","DEFAULT_ABILITY"})do
                    W.modifiers[#W.modifiers+1]={slot=slot,name=name};
                    if W.ability_partial then break end;
                end
            end
            if W.ability_throw_after then error("notification threw after attaching")end;
            return 1;
        end,
        SetCityStateIdentityText = function(slot,shortName,description,adjective)
            local cfg=W.cfgs[slot]; if not cfg then return nil end;
            if not W.identity_text_silent then
                cfg._short=shortName; cfg._description=description; cfg._adjective=adjective;
            end;
            return 1;
        end,
        ActivatePlayer = function(slot)
            W.calls.activate = W.calls.activate + 1;
            if W.activate_ret == 1 then
                W.native_activated[slot] = true;
                if W.players[slot] == nil then W.players[slot] = make_player(slot, false) end
                if W.activate_publishes_alive == true then W.players[slot]._alive = true end
                return 1;
            end
            -- ★ activate_partial = true → 模拟原生桥"注册/初始化做了一半才失败"：
            --   契约上返回 0/nil（= 没成功），但状态【已经被改动了】。
            --   这就是"失败 ≠ 状态没变"的模型，用来验证调用方是否保守隔离。
            if W.activate_partial == true then
                local c = W.cfgs[slot];
                if c ~= nil then c._status = 1 end
                local p = W.players[slot];
                if p ~= nil then p._alive = false end
            end
            return W.activate_ret;
        end,
        CreateCityNative = function(slot, x, y, _name)
            W.calls.create[#W.calls.create + 1] = { player = slot, x = x, y = y };
            if W.create_behavior == "throw" then
                error("stub: C6FW.CreateCityNative threw");
            end
            if W.create_behavior == "silent" then
                if W.on_create ~= nil then W.on_create(slot, x, y) end
                return 0;
            end
            if W.create_behavior == "count_only" then
                W.cities[#W.cities + 1] = make_city(slot, 0, 0);
                if W.on_create ~= nil then W.on_create(slot, x, y) end
                return 1;
            end
            W.cities[#W.cities + 1] = make_city(slot, x, y);
            if W.on_create ~= nil then W.on_create(slot, x, y) end
            return 1;
        end,
        SetAlive = function(slot, v)
            W.calls.set_alive = W.calls.set_alive + 1;
            local p = W.players[slot];
            if p == nil then return nil end
            if W.set_alive_ret ~= 1 then return W.set_alive_ret end
            p._alive = (v ~= 0);
            return 1;
        end,
        GetAlive = function(slot)
            local p = W.players[slot];
            if p == nil then return nil end
            if p._alive then return 1 end
            return nil;
        end,
        GetPlayerColorBySlot = function(slot)
            local c = W.cfgs[slot];
            if c == nil then return nil end
            return c._color;
        end,
        CopyPlayerColor = function(src, dst)
            -- ★ ok_false → 模拟"原生桥返回布尔 false"：契约上不是合法颜色值，
            --   旧 hasColor（只判不是 nil/0/-1/0xffffffff）会把它当成功。
            if W.color_mode == "ok_false" then return false end
            if W.color_mode ~= "ok" then return nil end
            local s = W.cfgs[src];
            local d = W.cfgs[dst];
            if s == nil or d == nil or s._color == nil then return nil end
            d._color = s._color;
            return d._color;
        end,
        SetPlayerColorBySlot = function(slot, color)
            if W.color_mode == "ok_false" then return false end
            if W.color_mode ~= "ok" then return nil end
            local d = W.cfgs[slot];
            if d == nil then return nil end
            d._color = color;
            return d._color;
        end,
        -- 原生“装配城邦 AI 回合任务”桥。生产只 pcall 它并读回三向量，
        -- 不看返回值，所以这里用行为模式模拟成功/静默/部分/抛错。
        InitializeCityStateTurnTasks = function(slot)
            W.calls.init_turn_tasks = W.calls.init_turn_tasks + 1;
            local mode = W.init_tasks_behavior or "ok";
            if mode == "throw" then
                error("stub: InitializeCityStateTurnTasks threw");
            end
            if mode == "silent" then
                return 1;                      -- 返回 1，但一个任务也没装
            end
            if mode == "partial" then
                W.turn_tasks[slot] = {15, 0, 0}; -- 只补齐了第一部分
                return 1;
            end
            W.turn_tasks[slot] = {15, 6, 3};
            if mode == "throw_after" then
                error("stub: InitializeCityStateTurnTasks threw after assembling");
            end
            return 1;
        end,
    };

    -- 默认就是原生 good 快照：既有用例不设 snapshot_mode 也能通过新 preflight；
    -- "bad" 仍保留原来的坏列表语义。任务三向量/容量/owner/可读性均可按槽编程。
    C6FW.GetPlayerSnapshot = function(slot)
        local good = W.snapshot_mode ~= "bad";
        local tasks = W.turn_tasks[slot] or {0, 0, 0};
        local caps = W.turn_task_caps[slot] or {256, 256, 256};
        return {
            read_status = 0, global_read_status = 0, city_state_read_status = 0,
            global_list_state = good and 5 or 3,
            city_state_list_state = good and 5 or 3,
            global_bad_member_pointer_count = 0, global_bad_member_id_count = 0,
            city_state_bad_member_pointer_count = 0, city_state_bad_member_id_count = 0,
            target_slot = slot, target_slot_valid = 1, target_pointer_found = 1,
            global_target_pointer_hits = 2, global_target_slot_hits = 3,
            city_state_target_pointer_hits = 2, city_state_target_slot_hits = 3,
            target_slot_id_read = 1, target_slot_id = slot,
            target_alive_read = 1, target_alive = 1,
            target_initialized_read = 1, target_initialized = 1,
            target_turn_tasks_read = W.turn_task_read and 1 or 0,
            owner_matches = W.turn_task_owner_matches and 1 or 0,
            target_turn_tasks_a_size = tasks[1],
            target_turn_tasks_b_size = tasks[2],
            target_turn_tasks_c_size = tasks[3],
            target_turn_tasks_a_capacity = caps[1],
            target_turn_tasks_b_capacity = caps[2],
            target_turn_tasks_c_capacity = caps[3],
        };
    end;
    if W.native_status_mode ~= nil then
        C6FW.GetNativeSlotStatus = function(_slot)
            return W.native_status_mode == "good" and 1 or 5;
        end;
    else
        -- 新版源码把“预注册休眠槽”与“已有游戏侧 Player”作为硬门禁；
        -- 夹具也提供这两个只读契约，避免测试因为缺少桩 API 而退化成 no_free_slot。
        C6FW.GetNativeSlotStatus = function(slot)
            local c = W.cfgs[slot];
            if W.native_activated[slot] == true and c ~= nil then return 1 end
            return c and c._status or nil;
        end;
    end
    C6FW.HasGamePlayer = function(slot)
        return W.players[slot] ~= nil and W.players[slot]._alive == true and 1 or 0;
    end
    if W.closed_fixture then
        C6FW.PreparePlayerIdentity = function() error("closed slot must use closed preparation"); end;
        C6FW.PrepareClosedCityState = function(slot, civ, leader)
            W.prepare_closed_calls = (W.prepare_closed_calls or 0) + 1;
            if W.prepare_closed_silent then return 1 end
            local cfg = W.cfgs[slot]; cfg._civ = civ; cfg._leader = leader;
            cfg._level = "CIVILIZATION_LEVEL_CITY_STATE"; cfg._status = 5;
            return 1;
        end;
        GameInfo.CivilizationLeaders = function()
            local sent = false;
            return function() if not sent then sent=true; return {CivilizationType=TARGET_CIV, LeaderType="LEADER_MINOR_CIV_ANTANANARIVO"}; end end;
        end;
    end

    print = function(...)
        local t = {};
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        LOG[#LOG + 1] = table.concat(t, " ");
    end;
end

-- ------------------------------------------------------------------ 装载脚本
local function load_scripts(fill)
    new_world();
    fill(W);
    install_env();
    log_clear();
    ExposedMembers = {};
    -- 与 modinfo 的 AddGameplayScripts 顺序一致
    dofile(F_GAMEPLAY);
    dofile(F_CREATE);
    return ExposedMembers;
end

--------------------------------------------------------------------------------
-- 场景构造helper
--------------------------------------------------------------------------------
local function add_target_slot(slot)
    W.cfgs[slot] = make_cfg({ civ = TARGET_CIV, leader = "LEADER_MINOR_CIV_ANTANANARIVO",
                              level = "CIVILIZATION_LEVEL_CITY_STATE", status = 5, color = nil });
    W.players[slot] = make_player(slot, false);
end

local function base_fill(W)
    -- 玩家 0 = 建邦者（使节站在目标格上，与实机一致）
    W.players[0] = make_player(0, true);
    W.cfgs[0] = make_cfg({ civ = "CIVILIZATION_ROME", leader = "LEADER_TRAJAN",
                           level = "CIVILIZATION_LEVEL_FULL_CIV", status = 0, color = 5 });
    add_target_slot(TARGET_SLOT);
    -- 场上另一个已激活的城邦（提供补色来源）
    W.players[7] = make_player(7, true);
    W.cfgs[7] = make_cfg({ civ = OTHER_CIV, leader = "LEADER_MINOR_CIV_ZANZIBAR",
                           level = "CIVILIZATION_LEVEL_CITY_STATE", status = 1, color = 3 });
    W.alive_minors = { 7 };
end

local function add_envoy(x, y)
    return add_unit(0, 0, x, y);        -- 0 = UNIT_CSF_ENVOY
end

-- 共同的调用入口
local function found(E, civ, x, y, unitID, ownerID)
    return E.CSF.FoundCityStateByCiv(civ, x, y, unitID, ownerID);
end

--------------------------------------------------------------------------------
-- T3e 新版 C6FW 已在 ActivatePlayer 内发布 alive：Lua 不得重复重建列表
--------------------------------------------------------------------------------
local function T3e_native_activate_already_published_alive()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.activate_publishes_alive = true;
        Wx.snapshot_mode = "good";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);
    check("T3e.1 原生已发布 alive 时建邦成功", ok == true and reason == "ok",
          "ok=" .. tostring(ok) .. " reason=" .. tostring(reason));
    check("T3e.2 已发布 alive 时不重复调用 SetAlive", W.calls.set_alive == 0,
          "set_alive=" .. tostring(W.calls.set_alive));
    check("T3e.3 仍只建一座目标城", #W.calls.create == 1,
          "create=" .. tostring(#W.calls.create));
    check("T3e.4 成功路径没有隔离槽", W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] == nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
end

local function T3f_native_snapshot_rejects_bad_lists()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.activate_publishes_alive = true;
        Wx.snapshot_mode = "bad";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);
    check("T3f.1 原生快照发现坏列表时不返回成功", ok ~= true,
          "ok=" .. tostring(ok));
    check("T3f.2 原生快照失败原因可识别", tostring(reason):find("native_snapshot_", 1, true) == 1,
          "reason=" .. tostring(reason));
    check("T3f.3 原生快照失败不建城且隔离槽", #W.calls.create == 0 and
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "create=" .. tostring(#W.calls.create) .. " iso=" ..
          tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
end

local function T3g_native_status_crosscheck_rejects_wrong_state()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.activate_publishes_alive = true;
        Wx.snapshot_mode = "good";
        Wx.native_status_mode = "bad";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);
    check("T3g.1 原生槽位状态不一致时不返回成功", ok ~= true,
          "ok=" .. tostring(ok));
    check_eq("T3g.2 原生槽位状态失败原因", tostring(reason), "native_status_wrong");
    check("T3g.3 原生槽位状态失败不建城且隔离", #W.calls.create == 0 and
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "create=" .. tostring(#W.calls.create) .. " iso=" ..
          tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
end

--------------------------------------------------------------------------------
-- T1 开局：LoadScreenClose 必须是"明确无操作"
--------------------------------------------------------------------------------
local function T1_startup_noop()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        Wx.turn = 1;
        -- 再塞几个休眠城邦玩家，模拟"池子里有、没激活"的局面。
        -- ★ 必须让它们进 GetAliveMinorIDs()：修改前的 LoadScreenClose 会按比例
        --   （CSF_KEEP_ACTIVE_PERCENT）把这些玩家"预留"到地图外，
        --   这一步正是本用例要证明【已经不会发生】的行为。
        for _, s in ipairs({ 30, 31, 32 }) do
            Wx.cfgs[s] = make_cfg({ civ = OTHER_CIV, level = "CIVILIZATION_LEVEL_CITY_STATE", status = 5 });
            Wx.players[s] = make_player(s, true);
            add_unit(s, 1, -1, -1);         -- 地图外移民（预留态）
        end
        Wx.alive_minors = { 7, 30, 31, 32 };
    end);

    check("T1.1 注册了 LoadScreenClose 处理器", HOOKS.lsc ~= nil, "hook=" .. tostring(HOOKS.lsc));

    local kills_before = W.calls.kill;
    local units_before = #W.units;
    if HOOKS.lsc ~= nil then HOOKS.lsc(); end

    check("T1.2 开局不移走任何城邦单位（无单位被删）",
          W.calls.kill == kills_before, "kill=" .. tostring(W.calls.kill));
    check("T1.3 开局不额外造城邦（无 InitUnit）",
          #W.calls.init_unit == 0, "init_unit=" .. tostring(#W.calls.init_unit));
    check("T1.4 开局不额外造城邦（无 AddPlayer）",
          W.calls.add_player == 0, "add_player=" .. tostring(W.calls.add_player));
    check("T1.5 开局不建任何城（无 Create）",
          #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T1.6 开局不消耗任何单位（单位总数不变）",
          #W.units == units_before, "units=" .. tostring(#W.units));
    check("T1.7 开局预留函数没有被自动调用（日志无 reserve done）",
          not log_has("reserve done"), "log=" .. log_text():sub(1, 200));
end

--------------------------------------------------------------------------------
-- T2 非法地块：不得激活、不得消耗使节、不得建城
--------------------------------------------------------------------------------
local function T2_invalid_plot()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        -- 整张地图全是水 → 目标格非法，且全地图找不到可建邦的格
        for x = 0, Wx.gw - 1 do
            for y = 0, Wx.gh - 1 do Wx.plot_water[key2(x, y)] = true end
        end
        add_envoy(10, 10);
    end);

    local envoy = UnitManager.GetUnit(0, 1001);
    check("T2.0 前置：使节在场上", envoy ~= nil, "envoy=" .. tostring(envoy));

    local ok, reason = found(E, TARGET_CIV, 10, 10, envoy and envoy:GetID() or nil, 0);

    check("T2.1 非法地块不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T2.2 原因 = water", tostring(reason), "water");
    check("T2.3 没有激活槽（激活必须在校验之后）",
          W.calls.activate == 0, "activate=" .. tostring(W.calls.activate));
    check("T2.4 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
    check("T2.5 没有调用 Create", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T2.6 没有把槽标成隔离（还没动过它）",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] == nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
end

--------------------------------------------------------------------------------
-- T3 原生激活失败：必须如实报错，不能吞掉原因
--------------------------------------------------------------------------------
local function T3_activate_failure()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.activate_ret = nil;          -- C6FW.ActivatePlayer 失败（契约：返 nil）
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T3.1 激活失败不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check("T3.2 原因含 activate（不是含糊的 no_free_slot）",
          tostring(reason):find("activate", 1, true) ~= nil, "reason=" .. tostring(reason));
    check("T3.3 试过激活", W.calls.activate == 1, "activate=" .. tostring(W.calls.activate));
    check("T3.4 没有置 IsAlive", W.calls.set_alive == 0, "set_alive=" .. tostring(W.calls.set_alive));
    check("T3.5 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
    check("T3.6 没有调用 Create", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T3.7 调用过原生激活但没成功 → 保守隔离（不接受「状态没变」的假设）",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check_eq("T3.8 隔离原因 = 原生失败原码",
             tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]), "activate_player_failed");
    check("T3.9 没有回滚（没有 SetAlive(0) / UninitializePlayer）",
          W.calls.set_alive == 0 and #W.calls.uninit == 0,
          "set_alive=" .. tostring(W.calls.set_alive) .. " uninit=" .. tostring(#W.calls.uninit));
end

--------------------------------------------------------------------------------
-- T3d 原生"改了一半状态"才失败：失败 ≠ 状态没变，必须保守隔离且不回滚
--------------------------------------------------------------------------------
local function T3d_partial_activate_failure()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.activate_ret = 0;            -- 契约上"没成功"
        Wx.activate_partial = true;     -- 但注册/初始化已经改了一部分状态
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T3d.1 部分初始化后失败 → 不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T3d.2 原因 = activate_player_failed", tostring(reason), "activate_player_failed");
    check("T3d.3 前置事实：状态确实已被改动（不是干净的 5）",
          W.cfgs[TARGET_SLOT] ~= nil and W.cfgs[TARGET_SLOT]._status == 1,
          "status=" .. tostring(W.cfgs[TARGET_SLOT] and W.cfgs[TARGET_SLOT]._status));
    check("T3d.4 已改过状态的槽被保守隔离",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T3d.5 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
    check("T3d.6 没有调用 Create", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T3d.7 没有回滚（没有 SetAlive(0) / UninitializePlayer / 没造第二个孤儿）",
          W.calls.set_alive == 0 and #W.calls.uninit == 0 and W.calls.add_player == 0,
          "set_alive=" .. tostring(W.calls.set_alive) ..
          " uninit=" .. tostring(#W.calls.uninit) ..
          " add_player=" .. tostring(W.calls.add_player));

    -- 下一回合再试：隔离槽必须被跳过，不会重复同一个失败
    W.turn = 11;
    local ok2, _ = found(E, TARGET_CIV, 10, 10, 1002, 0);
    check("T3d.8 下一回合不再挑这个隔离槽（没有第二次激活尝试）",
          W.calls.activate == 1 and ok2 ~= true,
          "activate=" .. tostring(W.calls.activate) .. " ok2=" .. tostring(ok2));
end

--------------------------------------------------------------------------------
-- T3b SetAlive 返回 0（非 1 的非 nil 值）：必须判失败并隔离
--------------------------------------------------------------------------------
local function T3b_setalive_failure()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.set_alive_ret = 0;           -- 原实现只判 nil → 会把 0 当成功
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T3b.1 SetAlive=0 不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T3b.2 原因 = set_alive_failed", tostring(reason), "set_alive_failed");
    check("T3b.3 激活已发生 → 槽被隔离",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T3b.4 没有调用 Create", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T3b.5 没有造第二个孤儿（无 AddPlayer）",
          W.calls.add_player == 0, "add_player=" .. tostring(W.calls.add_player));
end

--------------------------------------------------------------------------------
-- T3c 补色失败：不再被忽略（无颜色城邦会崩旗标渲染）
--------------------------------------------------------------------------------
local function T3c_no_color()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.color_mode = "fail";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T3c.1 补色失败不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T3c.2 原因 = no_color", tostring(reason), "no_color");
    check("T3c.3 槽被隔离（激活已发生、不可回滚）",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T3c.4 没有调用 Create", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T3c.5 没有消耗使节（建城前就失败了）",
          W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
end

--------------------------------------------------------------------------------
-- T4 Create 抛异常
--------------------------------------------------------------------------------
local function T4_create_threw()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.create_behavior = "throw";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T4.1 Create 抛异常不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T4.2 原因 = create_threw", tostring(reason), "create_threw");
    check("T4.3 尝试过 Create", #W.calls.create == 1, "create=" .. tostring(#W.calls.create));
    check("T4.4 槽被隔离", W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T4.5 没有盲目回滚（IsAlive 仍为 true）",
          W.players[TARGET_SLOT] ~= nil and W.players[TARGET_SLOT]._alive == true,
          "alive=" .. tostring(W.players[TARGET_SLOT] and W.players[TARGET_SLOT]._alive));
    check("T4.6 没有造第二个孤儿（无 AddPlayer）",
          W.calls.add_player == 0, "add_player=" .. tostring(W.calls.add_player));
end

--------------------------------------------------------------------------------
-- T5 静默 0 城（引擎报 OK 但没建城）
--------------------------------------------------------------------------------
local function T5_silent_zero_city()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.create_behavior = "silent";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T5.1 静默 0 城不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T5.2 原因 = create_silent_fail", tostring(reason), "create_silent_fail");
    check("T5.3 槽被隔离", W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T5.4 目标格上没有城市",
          Cities.GetCityInPlot(10, 10) == nil, "plot_city=nil");
    check("T5.5 本回合没有被记成'建过'（失败不烧回合）",
          W.props["CSF_LastFoundTurn"] == nil,
          "last=" .. tostring(W.props["CSF_LastFoundTurn"]));
end

--------------------------------------------------------------------------------
-- T6 ★核心回归：别处已有城、目标格没城 —— 旧实现判成功，现在必须判失败
--------------------------------------------------------------------------------
local function T6_city_elsewhere_not_at_target()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        -- 该槽自己在别处已经有一座城（城市总数 ≥ 1）
        Wx.cities[#Wx.cities + 1] = make_city(TARGET_SLOT, 2, 2);
        Wx.create_behavior = "silent";
    end);

    check("T6.0 前置：该槽城市总数 = 1", #live_cities(TARGET_SLOT) == 1,
          "count=" .. tostring(#live_cities(TARGET_SLOT)));

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T6.1 别处有城但目标格没城 → 不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T6.2 原因 = create_silent_fail", tostring(reason), "create_silent_fail");
    check("T6.3 目标格仍无城市", Cities.GetCityInPlot(10, 10) == nil, "target_city=nil");
    check("T6.4 槽被隔离", W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
end

--------------------------------------------------------------------------------
-- T7 队列：重复请求 + 同队列重入
--------------------------------------------------------------------------------
local function T7_queue_duplicate_and_reentrancy()
    local E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); add_envoy(12,12); end);

    -- 第一次 Create 期间：① 再塞另一个真实使节的请求 ② 重入 GameCoreEventPublishComplete
    local first = true;
    W.on_create = function(_id, _x, _y)
        if not first then return end
        first = false;
        E.CSF.RequestFound(TARGET_CIV, 12, 12, 1002, 0);
        if HOOKS.gce ~= nil then HOOKS.gce(); end
    end;

    local queued, requestID = E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0);
    check("T7.1 请求入队成功", queued == true, "queued");
    check("T7.1b 入队返回请求关联号", type(requestID) == "number" and requestID > 0, tostring(requestID));
    HOOKS.gce();                                  -- 处理队列

    check("T7.2 同一个回合只建了 1 座城（重入被挡住）",
          #W.calls.create == 1, "create=" .. tostring(#W.calls.create));
    check("T7.3 重入被明确拒绝（日志有记录）",
          log_has("忽略这次重入"), "log_tail=" .. log_text():sub(-300));
    check("T7.4 成功被记入本回合",
          W.props["CSF_LastFoundTurn"] == 10, "last=" .. tostring(W.props["CSF_LastFoundTurn"]));
    check("T7.5 已经广播过 1 条成功结果",
          #W.broadcast == 1 and W.broadcast[1].ok == true,
          "n=" .. tostring(#W.broadcast) .. " ok=" .. tostring(W.broadcast[1] and W.broadcast[1].ok));

    -- 面板真正读的就是 GetLastResult（CSF_Panel.lua 调 ExposedMembers.CSF.GetLastResult）
    local qSeq, qOk, qReason, qPlayer, qX, qY, qRequestID, qOwnerID = E.CSF.GetLastResult();
    check_eq("T7.5c 轮询结果关联原请求", qRequestID, requestID);
    check_eq("T7.5d 轮询结果保留发起玩家", qOwnerID, 0);
    check("T7.5b 面板读到的结果 = 成功（seq/ok/reason/player/x/y）",
          qSeq ~= nil and qOk == true and tostring(qReason) == "ok"
          and tonumber(qPlayer) == TARGET_SLOT and tonumber(qX) == 10 and tonumber(qY) == 10,
          "seq=" .. tostring(qSeq) .. " ok=" .. tostring(qOk) .. " reason=" .. tostring(qReason) ..
          " player=" .. tostring(qPlayer) .. " x=" .. tostring(qX) .. " y=" .. tostring(qY));

    -- 同回合再来一次（正常事件推进）：限流器必须拒绝
    HOOKS.gce();
    check("T7.6 同回合第二次请求被限流（one_per_turn）",
          W.broadcast[#W.broadcast] ~= nil and tostring(W.broadcast[#W.broadcast].reason) == "one_per_turn",
          "last_reason=" .. tostring(W.broadcast[#W.broadcast] and W.broadcast[#W.broadcast].reason));
    check("T7.7 限流后仍然只有 1 座城",
          #W.calls.create == 1, "create=" .. tostring(#W.calls.create));
end

--------------------------------------------------------------------------------
-- T8 失败不烧回合 + 隔离槽不再被选
--------------------------------------------------------------------------------
local function T8_failure_does_not_burn_turn()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_target_slot(TARGET_SLOT2);      -- 同一文明的第二个预注册槽
        add_envoy(10, 10);
        Wx.create_behavior = "silent";      -- 第一次：静默失败
    end);

    local ok1, reason1 = found(E, TARGET_CIV, 10, 10, 1001, 0);
    check("T8.1 第一次失败", ok1 ~= true and tostring(reason1) == "create_silent_fail",
          "ok=" .. tostring(ok1) .. " reason=" .. tostring(reason1));
    check("T8.2 失败没有消耗本回合额度",
          W.props["CSF_LastFoundTurn"] == nil,
          "last=" .. tostring(W.props["CSF_LastFoundTurn"]));

    -- 同回合重试：必须被允许（不是 one_per_turn），这次 Create 成功
    W.create_behavior = "ok";
    local ok2, reason2, slot2 = found(E, TARGET_CIV, 10, 10, 1001, 0);
    check("T8.3 失败后同回合重试不被 'one_per_turn' 挡",
          tostring(reason2) ~= "one_per_turn", "reason=" .. tostring(reason2));
    check("T8.4 重试成功", ok2 == true and tostring(reason2) == "ok",
          "ok=" .. tostring(ok2) .. " reason=" .. tostring(reason2));
    check_eq("T8.5 重试用的是【没被隔离的】另一个槽", tonumber(slot2), TARGET_SLOT2);
    check("T8.6 第一次失败的槽被标记隔离",
          tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]) == "create_silent_fail",
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T8.7 成功后本回合额度被占用",
          W.props["CSF_LastFoundTurn"] == 10, "last=" .. tostring(W.props["CSF_LastFoundTurn"]));
end

--------------------------------------------------------------------------------
-- T9 成功：真实建城 + 只提交一次
--------------------------------------------------------------------------------
local function T9_success_once()
    local E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); end);

    local ok, reason, slot, bFull = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T9.1 返回成功", ok == true, "ok=" .. tostring(ok));
    check_eq("T9.2 原因 = ok", tostring(reason), "ok");
    check_eq("T9.3 建在目标槽上", tonumber(slot), TARGET_SLOT);
    check("T9.4 标记为完整机制", bFull == true, "bFull=" .. tostring(bFull));
    check("T9.5 只调用了一次 Create", #W.calls.create == 1, "create=" .. tostring(#W.calls.create));
    check("T9.6 Create 落在目标格 (10,10)",
          #W.calls.create == 1 and W.calls.create[1].x == 10 and W.calls.create[1].y == 10,
          "x=" .. tostring(W.calls.create[1] and W.calls.create[1].x) ..
          " y=" .. tostring(W.calls.create[1] and W.calls.create[1].y));
    local c = Cities.GetCityInPlot(10, 10);
    check("T9.7 目标格确有城市且属于该槽",
          c ~= nil and c:GetOwner() == TARGET_SLOT,
          "city=" .. tostring(c ~= nil) .. " owner=" .. tostring(c and c:GetOwner()));
    check("T9.8 使节恰好被消耗一次", W.calls.kill == 1, "kill=" .. tostring(W.calls.kill));
    check("T9.9 使节不在场上了",
          #live_units(0) == 0, "units=" .. tostring(#live_units(0)));
    check("T9.10 本回合额度已记（存档属性）",
          W.props["CSF_LastFoundTurn"] == 10, "last=" .. tostring(W.props["CSF_LastFoundTurn"]));
    check("T9.11 没有隔离标记",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] == nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T9.12 没有造额外玩家（无 AddPlayer）",
          W.calls.add_player == 0, "add_player=" .. tostring(W.calls.add_player));
    -- 说明：广播 / 面板结果只在【队列路径】里产生（T7 覆盖），
    --       这里是直接调核心函数，所以不检查 W.broadcast。

    -- 同回合再提交一次 → 必须被限流，且不再建城
    local ok2, reason2 = found(E, TARGET_CIV, 11, 11, nil, 0);
    check("T9.14 同回合重复提交被限流", tostring(reason2) == "one_per_turn",
          "reason=" .. tostring(reason2));
    check("T9.15 重复提交没有第二次 Create", #W.calls.create == 1,
          "create=" .. tostring(#W.calls.create));
end

--------------------------------------------------------------------------------
-- T10 隔离槽不再被挑中（半激活失败后，该槽既没死也不能再用）
--     场景：ActivatePlayer 成功、SetAlive 返回 0 → 槽被激活但没活起来。
--     这种槽必须被隔离，且下一回合不能再被当成正常目标提交。
--------------------------------------------------------------------------------
local function T10_isolated_slot_not_picked()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.set_alive_ret = 0;              -- 激活半途失败：IsAlive 仍为 false
    end);

    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0);
    HOOKS.gce();
    check("T10.1 半激活失败 → 如实报 set_alive_failed，不报成功",
          #W.broadcast == 1 and W.broadcast[1].ok ~= true
          and tostring(W.broadcast[1].reason) == "set_alive_failed",
          "reason=" .. tostring(W.broadcast[1] and W.broadcast[1].reason));
    check("T10.2 没有建城", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T10.3 槽既没活也没建城，但被记了隔离",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));

    W.turn = W.turn + 1;                   -- 换回合，排除限流干扰
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0);
    HOOKS.gce();
    check("T10.4 下一回合不再挑这个隔离槽（跳过日志可见）",
          log_has("跳过已隔离的槽 " .. TARGET_SLOT),
          "命中=" .. tostring(log_has("跳过已隔离的槽 " .. TARGET_SLOT)));
    check("T10.5 没有第二次激活尝试（隔离槽被挡在激活之前）",
          W.calls.activate == 1, "activate=" .. tostring(W.calls.activate));
    check("T10.6 缺少原生桥时如实返回 no_identity_bridge",
          #W.broadcast == 2 and tostring(W.broadcast[2].reason) == "no_identity_bridge",
          "reason=" .. tostring(W.broadcast[2] and W.broadcast[2].reason));
    check("T10.7 全程没有建任何城",
          #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
end

--------------------------------------------------------------------------------
-- T11 CSF_FoundCityState 自身的目标格取证 + 使节补偿
--------------------------------------------------------------------------------
local function T11_found_city_state_target_check()
    -- A：城市数变了但目标格没城 → 必须判失败（旧实现只看城市数，会报成功）
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(12, 12);
        Wx.players[54] = make_player(54, true);
        Wx.cfgs[54] = make_cfg({ civ = TARGET_CIV, level = "CIVILIZATION_LEVEL_CITY_STATE", status = 1 });
        Wx.create_behavior = "count_only";
    end);

    local okA, reasonA = E.CSF.FoundCityState(54, 10, 10, 1001, 0);
    check("T11.1 城市数变了但目标格没城 → 不返回成功", okA ~= true, "ok=" .. tostring(okA));
    check_eq("T11.2 原因 = silent_fail", tostring(reasonA), "silent_fail");
    check("T11.3 目标格无城市", Cities.GetCityInPlot(10, 10) == nil, "target=nil");
    check("T11.4 补偿：在同格重生了一个使节",
          #W.calls.init_unit == 1
          and W.calls.init_unit[1].unit_type == "UNIT_CSF_ENVOY"
          and W.calls.init_unit[1].x == 10 and W.calls.init_unit[1].y == 10,
          "init=" .. tostring(#W.calls.init_unit) ..
          " type=" .. tostring(W.calls.init_unit[1] and W.calls.init_unit[1].unit_type));

    -- B：真实成功
    local E2 = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(12, 12);
        Wx.players[54] = make_player(54, true);
        Wx.cfgs[54] = make_cfg({ civ = TARGET_CIV, level = "CIVILIZATION_LEVEL_CITY_STATE", status = 1 });
        Wx.create_behavior = "ok";
    end);
    local okB, reasonB = E2.CSF.FoundCityState(54, 10, 10, 1001, 0);
    local c = Cities.GetCityInPlot(10, 10);
    check("T11.5 正常路径返回成功", okB == true, "ok=" .. tostring(okB) .. " reason=" .. tostring(reasonB));
    check("T11.6 目标格确有属于 54 的城市",
          c ~= nil and c:GetOwner() == 54, "owner=" .. tostring(c and c:GetOwner()));
end

--------------------------------------------------------------------------------
-- T12 槽位状态没被改成 AI(1)：引擎的状态门禁会静默拒绝，必须判失败
--------------------------------------------------------------------------------
local function T12_status_gate()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.status_set_effective = false;    -- SetPlayerSlotStatus 无效，槽仍是 5
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T12.1 槽位状态没改成功 → 不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T12.2 原因 = post_status_still_5", tostring(reason), "post_status_still_5");
    check("T12.3 槽被隔离（激活已发生、不可回滚）",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T12.4 没有调用 Create", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T12.5 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
end

--------------------------------------------------------------------------------
-- T13 公共导出 ForceReserve：开局预留实验不可再被任何入口触发
--------------------------------------------------------------------------------
local function T13_force_reserve_disabled()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        Wx.turn = 1;
        for _, s in ipairs({ 30, 31, 32 }) do
            Wx.cfgs[s] = make_cfg({ civ = OTHER_CIV, level = "CIVILIZATION_LEVEL_CITY_STATE", status = 5 });
            Wx.players[s] = make_player(s, true);
            add_unit(s, 1, -1, -1);
        end
        Wx.alive_minors = { 7, 30, 31, 32 };
    end);

    check("T13.1 公共导出里仍有 ForceReserve 入口（探针/UI 可能调它）",
          E.CSF.ForceReserve ~= nil, "type=" .. type(E.CSF.ForceReserve));

    local units_before = #W.units;
    local ok, reason = nil, nil;
    if E.CSF.ForceReserve ~= nil then ok, reason = E.CSF.ForceReserve(); end

    check("T13.2 ForceReserve 已是明确无操作（返回 false）", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T13.3 原因 = startup_experiment_disabled", tostring(reason),
             "startup_experiment_disabled");
    check("T13.4 没有移走任何城邦单位（无 Kill、单位数不变）",
          W.calls.kill == 0 and #W.units == units_before,
          "kill=" .. tostring(W.calls.kill) .. " units=" .. tostring(#W.units));
    check("T13.5 没有额外造城邦（无 InitUnit / 无 AddPlayer）",
          #W.calls.init_unit == 0 and W.calls.add_player == 0,
          "init_unit=" .. tostring(#W.calls.init_unit) ..
          " add_player=" .. tostring(W.calls.add_player));
    check("T13.6 没有执行预留（日志无 reserve done）",
          not log_has("reserve done"), "log=" .. log_text():sub(1, 160));
end

--------------------------------------------------------------------------------
-- T14 补色：布尔 false 不是合法颜色（旧 hasColor 会把它当成功）
--------------------------------------------------------------------------------
local function T14_color_false_not_valid()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.color_mode = "ok_false";     -- 原生桥返回布尔 false = 非法颜色值
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T14.1 布尔 false 不算合法颜色 → 补色不可证 → 不返回成功",
          ok ~= true, "ok=" .. tostring(ok));
    check_eq("T14.2 原因 = no_color", tostring(reason), "no_color");
    check("T14.3 槽被隔离（激活已发生，只隔离不回滚）",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T14.4 没有建城（颜色不可证就不建）", #W.calls.create == 0,
          "create=" .. tostring(#W.calls.create));
    check("T14.5 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
end

--------------------------------------------------------------------------------
-- T15 槽位状态读不到（nil）：没有证据就不能宣称完整激活
--------------------------------------------------------------------------------
local function T15_status_unreadable()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        Wx.status_get_nil = true;       -- pm:GetSlotStatus 返回 nil
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T15.1 读不到槽位状态（nil）→ 不算激活成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T15.2 原因 = post_status_nil", tostring(reason), "post_status_nil");
    check("T15.3 槽被隔离",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T15.4 没有建城", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T15.5 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
end

--------------------------------------------------------------------------------
-- T16 激活后等级不是城邦：机制不完整，不能宣称完整激活
--------------------------------------------------------------------------------
local function T16_level_wrong()
    local E = load_scripts(function(Wx)
        base_fill(Wx);
        add_envoy(10, 10);
        -- 引擎没按城邦等级初始化（等级决定 CanReceiveInfluence）
        Wx.cfgs[TARGET_SLOT]._level = "CIVILIZATION_LEVEL_FULL_CIV";
    end);

    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);

    check("T16.1 等级不是城邦 → 不返回成功", ok ~= true, "ok=" .. tostring(ok));
    check_eq("T16.2 原因 = post_level_wrong", tostring(reason), "post_level_wrong");
    check("T16.3 槽被隔离",
          W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] ~= nil,
          "iso=" .. tostring(W.props["CSF_IsolatedSlot_" .. TARGET_SLOT]));
    check("T16.4 没有建城", #W.calls.create == 0, "create=" .. tostring(#W.calls.create));
    check("T16.5 没有消耗使节", W.calls.kill == 0, "kill=" .. tostring(W.calls.kill));
end

--------------------------------------------------------------------------------
-- 主流程
--------------------------------------------------------------------------------
local function T17_missing_native_does_not_quarantine()
    local E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); end);
    C6FW = nil;
    local ok, reason = found(E, TARGET_CIV, 10, 10, 1001, 0);
    check("T17.1 缺少原生桥如实失败", ok == false and reason == "no_c6fw", tostring(reason));
    check("T17.2 未调用激活", W.calls.activate == 0, tostring(W.calls.activate));
    check("T17.3 干净槽不应被永久隔离", W.props["CSF_IsolatedSlot_" .. TARGET_SLOT] == nil, "unchanged");
    check("T17.4 未消耗使节或建城", W.calls.kill == 0 and #W.calls.create == 0, "unchanged");
end

local function T18_founding_contact_and_reward()
    local E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); Wx.stock[0] = 4; end);
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0); HOOKS.gce();
    local _, ok = E.CSF.GetLastResult();
    check("T18.1 建城接触奖励均确认才成功", ok == true, tostring(ok));
    check("T18.2 双方已接触", W.contacts[key2(0,TARGET_SLOT)] and W.contacts[key2(TARGET_SLOT,0)], "mutual contact");
    check_eq("T18.3 实际奖励到账", W.tokens[key2(TARGET_SLOT,0)], 1);
    check_eq("T18.4 不消费库存使者", W.stock[0], 4);
    local saved = W.props["CSF_Founding_" .. TARGET_SLOT];
    check("T18.4b 恢复记录使用实际城市坐标", saved.X == 10 and saved.Y == 10, "actual xy");
    E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check_eq("T18.5 重复恢复不重复奖励", W.reward_calls, 1);
    local bad = E.CSF.CompleteFounding(TARGET_SLOT, 9);
    check("T18.6 别的玩家不能领取", bad == false, tostring(bad));
    -- 模拟 Lua VM 重载；保留同档引擎状态，奖励不能随脚本重载重复。
    dofile(F_GAMEPLAY); E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check_eq("T18.7 同档重载不重复奖励", W.reward_calls, 1);

    E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); Wx.contact_silent = true; end);
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0); HOOKS.gce();
    local _, contactOk, reason = E.CSF.GetLastResult();
    check("T18.8 静默未接触不得成功", contactOk == false and reason == "founding_contact_failed", tostring(reason));
    check_eq("T18.9 未接触不发奖励", W.reward_calls, 0);
    check_eq("T18.10 部分失败保留真实城市", #live_cities(TARGET_SLOT), 1);
    W.contact_silent = false;
    local repaired = E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check("T18.11 只恢复接触奖励不再次建城", repaired == true and #W.calls.create == 1, tostring(repaired));

    E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); Wx.reward_silent = true; end);
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0); HOOKS.gce();
    local _, rewardOk, rewardReason = E.CSF.GetLastResult();
    check("T18.12 静默未到账不得成功", rewardOk == false and rewardReason == "founding_envoy_unconfirmed", tostring(rewardReason));
    E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check_eq("T18.13 未知奖励结果不盲目重发", W.reward_calls, 1);

    E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); Wx.reward_throw_after = true; end);
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0); HOOKS.gce();
    local _, verifiedEffect = E.CSF.GetLastResult();
    check("T18.14 抛错但真实到账按读回确认", verifiedEffect == true and W.reward_calls == 1, tostring(verifiedEffect));

    E = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); Wx.contact_reward = true; end);
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0); HOOKS.gce();
    check_eq("T18.15 建邦奖励额外于引擎首次接触奖励", W.tokens[key2(TARGET_SLOT,0)], 2);
end

local function T19_closed_identity()
    local function fill(Wx)
        base_fill(Wx); Wx.players[TARGET_SLOT]=nil; Wx.cfgs[TARGET_SLOT]=nil;
        Wx.players[7]=nil; Wx.cfgs[7]=nil; Wx.alive_minors={}; Wx.closed_fixture=true;
        Wx.cfgs[6]=make_cfg({status=2}); Wx.cfgs[6]._level=nil;
        add_envoy(10,10);
    end
    local E=load_scripts(fill);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    local _,ok,reason,slot=E.CSF.GetLastResult();
    check("T19.1 零开局按请求登记并完整建邦",ok==true and slot==6,tostring(reason));
    check_eq("T19.2 仅登记一个空槽",W.prepare_closed_calls,1);
    check_eq("T19.3 不用AddPlayer",W.calls.add_player,0);
    check_eq("T19.4 有真实城市",#live_cities(6),1);
    check_eq("T19.5 身份正确",W.cfgs[6]._civ,TARGET_CIV);
    E=load_scripts(function(Wx) fill(Wx); Wx.prepare_closed_silent=true; end);
    local failed,why=found(E,TARGET_CIV,10,10,1001,0);
    check("T19.6 原生报成功但没设身份必须失败",failed==false and why=="closed_identity_failed",tostring(why));
    check_eq("T19.7 身份失败不激活不建城",W.calls.activate+#W.calls.create,0);
    check("T19.8 部分登记失败隔离",W.props.CSF_IsolatedSlot_6~=nil,"isolated");
    check("T19.9 不消耗使节",not W.units[1]._dead,"retained");
    E=load_scripts(function(Wx) fill(Wx); Wx.plot_water[key2(10,10)]=true; end);
    found(E,TARGET_CIV,10,10,1001,0);
    check("T19.10 非法地点不登记身份",W.prepare_closed_calls==nil,"no prepare");
    E=load_scripts(function(Wx) fill(Wx); Wx.props.CSF_IsolatedSlot_6="old_failure"; end);
    found(E,TARGET_CIV,10,10,1001,0);
    check("T19.11 失败槽不会再被分配",W.prepare_closed_calls==nil,"no prepare");
end

local function T20_defense_acceptance()
    local E=load_scripts(function(Wx) base_fill(Wx); add_envoy(10,10); end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    check_eq("T20.1 真正补齐原生基础战力",W.combat[TARGET_SLOT],20);
    W.combat[TARGET_SLOT]=60; E.CSF.RestoreCityStateDefense();
    check_eq("T20.2 读档恢复不降低已有高级战力",W.combat[TARGET_SLOT],60);
    W.combat[TARGET_SLOT]=0; HOOKS.lsc();
    check_eq("T20.3 已建城旧档恢复基础战力",W.combat[TARGET_SLOT],20);
    E=load_scripts(function(Wx) base_fill(Wx); add_envoy(10,10); Wx.defense_silent=true; end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    local _,ok,why=E.CSF.GetLastResult();
    check("T20.4 仍负城防不得报成功",ok==false and why=="founding_defense_unconfirmed",tostring(why));
    check_eq("T20.5 防御未确认不发使者奖励",W.reward_calls,0);
    check_eq("T20.6 未建邦普通城邦不被恢复改动",W.combat[7],nil);
end

local function T21_duplicate_closed_slot()
    local function fill(Wx)
        base_fill(Wx); Wx.players[TARGET_SLOT]=nil; Wx.cfgs[TARGET_SLOT]=nil;
        Wx.cfgs[7]._civ=TARGET_CIV; Wx.cfgs[7]._leader="LEADER_MINOR_CIV_ANTANANARIVO";
        Wx.cities[1]=make_city(7,2,2); Wx.closed_fixture=true;
        Wx.cfgs[6]=make_cfg({status=2}); Wx.cfgs[6]._level=nil;
        Wx.activate_publishes_alive=true; Wx.snapshot_mode="good";
        add_envoy(10,10);
    end
    local E=load_scripts(fill);
    local ok,why,slot=found(E,TARGET_CIV,10,10,1001,0);
    check("T21.1 副本优先使用空槽",ok==true and slot==6,tostring(why));
    check_eq("T21.2 原城邦保留真实城市",#live_cities(7),1);
    check_eq("T21.3 副本有独立真实城市",#live_cities(6),1);
    check_eq("T21.4 副本后缀持久化",W.props.CSF_CopySuffix_6," II");
    check_eq("T21.5 不走AddPlayer或UninitializePlayer",W.calls.add_player+#W.calls.uninit,0);
    E=load_scripts(function(Wx) fill(Wx); Wx.snapshot_mode="bad"; end);
    ok,why,slot=found(E,TARGET_CIV,10,10,1001,0);
    check("T21.6 注册后快照失败如实返回槽",ok==false and why=="snapshot_inconsistent" and slot==6,tostring(why));
    check_eq("T21.7 坏快照槽被持久隔离",W.props.CSF_IsolatedSlot_6,"snapshot_inconsistent");
    check_eq("T21.8 坏快照不建城不消费使节",#live_cities(6)+W.calls.kill,0);
    E=load_scripts(function(Wx) fill(Wx); Wx.create_behavior="silent"; end);
    ok,why,slot=found(E,TARGET_CIV,10,10,1001,0);
    check("T21.9 副本原生静默失败不成功",ok==false and slot==6,tostring(why));
    check("T21.10 静默失败槽被隔离",W.props.CSF_IsolatedSlot_6~=nil,"isolated");
end

local function T22_identity_text_acceptance()
    local E=load_scripts(function(Wx) base_fill(Wx); add_envoy(10,10); end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    check_eq("T22.1 原生短名正确",W.cfgs[TARGET_SLOT]._short,"LOC_TARGET_NAME");
    check_eq("T22.2 原生长名正确",W.cfgs[TARGET_SLOT]._description,"LOC_TARGET_DESCRIPTION");
    W.cfgs[TARGET_SLOT]._short=nil; W.cfgs[TARGET_SLOT]._description=nil; HOOKS.lsc();
    check_eq("T22.3 旧档空名称自动恢复",W.cfgs[TARGET_SLOT]._short,"LOC_TARGET_NAME");
    check_eq("T22.4 普通城邦不被恢复改名",W.cfgs[7]._short,nil);
    E=load_scripts(function(Wx) base_fill(Wx); add_envoy(10,10); Wx.identity_text_silent=true; end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    local _,ok,why=E.CSF.GetLastResult();
    check("T22.5 静默名称写入不得成功",ok==false and why=="founding_identity_text_unconfirmed",tostring(why));
    check_eq("T22.6 名称失败不发奖励",W.reward_calls,0);
end

local function T23_native_ability_acceptance()
    local function fill(Wx) base_fill(Wx); add_envoy(10,10); end;
    local E=load_scripts(fill);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    check_eq("T23.1 完整建邦通知一次",W.publish_ready_calls,1);
    check_eq("T23.2 继承能力也已注册",#W.modifiers,3);
    E.CSF.CompleteFounding(TARGET_SLOT,0); HOOKS.lsc();
    check_eq("T23.3 重复恢复不重复通知",W.publish_ready_calls,1);
    check_eq("T23.4 不重复叠加能力",#W.modifiers,3);
    check_eq("T23.5 不影响普通城邦能力",W.modifiers[1].slot,TARGET_SLOT);
    E=load_scripts(function(Wx)fill(Wx);Wx.ability_silent=true;end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    local _,ok,why=E.CSF.GetLastResult();
    check("T23.6 返回1但无能力不得成功",ok==false and why=="founding_abilities_unconfirmed",tostring(why));
    check_eq("T23.7 能力失败不发使者奖励",W.reward_calls,0);
    E.CSF.CompleteFounding(TARGET_SLOT,0); HOOKS.lsc();
    check_eq("T23.8 未知结果不得盲目重发通知",W.publish_ready_calls,1);
    E=load_scripts(function(Wx)fill(Wx);Wx.ability_partial=true;end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    _,ok,why=E.CSF.GetLastResult();
    check("T23.9 只注册部分能力不得成功",ok==false and why=="founding_abilities_unconfirmed",tostring(why));
    E.CSF.CompleteFounding(TARGET_SLOT,0);
    check_eq("T23.10 部分状态不重复全局通知",W.publish_ready_calls,1);
    E=load_scripts(function(Wx)fill(Wx);Wx.ability_throw_after=true;end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0); HOOKS.gce();
    _,ok=E.CSF.GetLastResult();
    check("T23.11 抛错但完整读回按实际效果确认",ok==true,tostring(ok));
    W.modifiers[#W.modifiers+1]={slot=TARGET_SLOT,name="TARGET_ABILITY"};
    local duplicate=E.CSF.CompleteFounding(TARGET_SLOT,0);
    check("T23.12 能力重复实例不得通过",duplicate==false,"duplicate rejected");
end

local function T24_native_operation_and_validation()
    local function fill(Wx)base_fill(Wx);add_envoy(10,10);end;
    local function send(id,extra)
        local p={CSF_Civ=TARGET_CIV,CSF_X=10,CSF_Y=10,CSF_UnitID=1001,CSF_RequestID=id};
        if extra then for k,v in pairs(extra)do p[k]=v end end;
        W.operation(0,p);
    end
    local E=load_scripts(fill);
    send(1,{OwnerID=7});HOOKS.gce();
    local _,ok,_,_,_,_,request,owner=E.CSF.GetLastResult(0);
    check("T24.1 原生回调发起者决定归属",ok==true and owner==0 and request==1,"actor authoritative");
    check_eq("T24.2 原生请求实际只建一城",#W.calls.create,1);
    send(1);HOOKS.gce();
    check_eq("T24.3 重放不重复建城",#W.calls.create,1);
    check_eq("T24.4 重放不重复奖励",W.reward_calls,1);
    dofile(F_GAMEPLAY);dofile(F_CREATE);send(1);HOOKS.gce();
    check_eq("T24.5 重载后仍拒绝已完成请求重放",#W.calls.create,1);
    local _,saved=ExposedMembers.CSF.GetLastResult(0);
    check("T24.6 分玩家结果持久可读",saved==true,"saved result");

    E=load_scripts(fill);W.units[1]._type=1;send(1);HOOKS.gce();
    local _,bad,why=E.CSF.GetLastResult(0);
    check("T24.7 普通开拓者不能建邦",bad==false and why=="request_unit_invalid",tostring(why));
    check_eq("T24.8 错误单位无引擎变动",W.calls.activate+#W.calls.create+W.calls.kill,0);

    E=load_scripts(fill);send(1);W.units[1]._x=11;HOOKS.gce();
    _,bad,why=E.CSF.GetLastResult(0);
    check("T24.9 排队后移动必须重新校验",bad==false and why=="request_unit_moved",tostring(why));
    check_eq("T24.10 移动后不注册不消耗",W.calls.activate+W.calls.kill,0);

    E=load_scripts(fill);send(1);W.units[1]._dead=true;HOOKS.gce();
    _,bad,why=E.CSF.GetLastResult(0);
    check("T24.11 排队后单位消失不得成功",bad==false and why=="request_unit_missing",tostring(why));
    check_eq("T24.12 消失后不造城",#W.calls.create,0);

    E=load_scripts(fill);send(1,{CSF_X="10"});HOOKS.gce();
    _,bad,why=E.CSF.GetLastResult(0);
    check("T24.13 非数字坐标不得执行",bad==false and why=="request_invalid",tostring(why));
    E=load_scripts(fill);send(1,{CSF_Civ="CIVILIZATION_ROME"});HOOKS.gce();
    _,bad,why=E.CSF.GetLastResult(0);
    check("T24.14 主要文明身份不能伪装城邦",bad==false and why=="request_civilization_invalid",tostring(why));

    E=load_scripts(fill);W.players[2]=make_player(2,true);
    W.cfgs[2]=make_cfg({civ="CIVILIZATION_ROME",level="CIVILIZATION_LEVEL_FULL_CIV"});
    W.operation(2,{CSF_Civ=TARGET_CIV,CSF_X=10,CSF_Y=10,CSF_UnitID=1001,CSF_RequestID=1,OwnerID=0});
    local _,foreign,foreignReason=E.CSF.GetLastResult(2);
    check("T24.15 其它玩家不能消费本方单位",foreign==false and foreignReason=="request_unit_missing",tostring(foreignReason));
    check_eq("T24.16 外方请求不杀单位",W.calls.kill,0);
    check_eq("T24.17 其它玩家结果不覆盖本方轮询",E.CSF.GetLastResult(0),0);

    E=load_scripts(fill);send(1);
    check("T24.18 已受理请求持久保存",type(W.props.CSF_SyncPending_0)=="table","pending persisted");
    dofile(F_GAMEPLAY);dofile(F_CREATE);HOOKS.lsc();HOOKS.lsc();HOOKS.gce();
    check_eq("T24.19 读档恢复待处理请求只执行一次",#W.calls.create,1);
    check_eq("T24.20 完成后清除待处理记录",W.props.CSF_SyncPending_0,nil);
    check_eq("T24.21 恢复不重复奖励",W.reward_calls,1);
end

local function T25_distance_and_isolated_identity()
    local E=load_scripts(function(Wx)base_fill(Wx);Wx.cities[1]=make_city(7,2,2);add_envoy(5,2);end);
    local valid,why=E.CSF.IsValidLocation(5,2,0);
    check("T25.1 三格排除半径边界拒绝",valid==false and why=="too_close",tostring(why));
    check("T25.2 四格合法陆地不被扩大拒绝",E.CSF.IsValidLocation(6,2,0)==true,"distance4");
    E.CSF.RequestFound(TARGET_CIV,5,2,1001,0);HOOKS.gce();
    check_eq("T25.3 距离前置失败不注册不消耗",W.calls.activate+W.calls.kill,0);
    GameInfo.GlobalParameters={CITY_MIN_RANGE={Value=4}};
    check("T25.4 读取实际规则参数",E.CSF.IsValidLocation(6,2,0)==false,"database range");
    E=load_scripts(function(Wx)base_fill(Wx);Wx.cities[1]=make_city(7,2,2);Wx.gw=6;Wx.gh=6;end);
    local x,y=E.CSF.FindFoundLocation(0);
    check("T25.5 拥挤找地不降级到不合法半径",x==nil or x<0 or y==nil or y<0,tostring(x)..","..tostring(y));
    E=load_scripts(function(Wx)base_fill(Wx);Wx.props.CSF_IsolatedSlot_7="test_failure";Wx.props.CSF_IsolatedSlot_41="before_alive";end);
    local rows=E.CSF.GetPublishedIdentities();
    check("T25.6 活跃失败槽同步真实身份",#rows==1 and rows[1].PlayerID==7 and rows[1].Isolated==true,"published");
    check_eq("T25.7 失败槽不冒充已建邦",#E.CSF.GetFoundedIdentities(),0);
    check_eq("T25.8 身份查询不注册能力",W.publish_ready_calls,nil);
    check_eq("T25.9 身份查询不创建城市",#W.calls.create,0);
    E=load_scripts(function(Wx)base_fill(Wx);Wx.props.CSF_IsolatedSlot_7="old_save";
        Wx.props.CSF_CopyOf_7=OTHER_CIV;Wx.cfgs[7]=make_cfg({status=2});Wx.cfgs[7]._level=nil;
        Wx.snapshot_mode="good";end);
    rows=E.CSF.GetPublishedIdentities();
    check("T25.10 旧档需原生分类与来源共同恢复镜像",#rows==1 and rows[1].Civ==OTHER_CIV,"provenance and native");
    W.snapshot_mode="bad";install_env();
    check_eq("T25.11 坏原生证据不猜身份",#E.CSF.GetPublishedIdentities(),0);
end

local function T26_reward_history_and_bridge_preflight()
    local E=load_scripts(function(Wx)base_fill(Wx);add_envoy(10,10);end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0);HOOKS.gce();
    W.tokens[key2(TARGET_SLOT,0)]=0;
    local ok,why=E.CSF.CompleteFounding(TARGET_SLOT,0);
    check("T26.1 宣战损失使者不抹掉建邦历史",ok==true,tostring(why));
    check_eq("T26.2 不补回合法游戏过程损失的使者",W.tokens[key2(TARGET_SLOT,0)],0);
    check_eq("T26.3 战后历史校验不重复发奖",W.reward_calls,1);
    for _,missing in ipairs({"PublishCityStateReady","SetCityStateIdentityText"})do
        E=load_scripts(function(Wx)base_fill(Wx);add_envoy(10,10);end);C6FW[missing]=nil;
        ok,why=found(E,TARGET_CIV,10,10,1001,0);
        check("T26.4 旧桥缺必需接口提前拒绝/"..missing,ok==false and why=="no_c6fw",tostring(why));
        check_eq("T26.5 缺接口不注册建城消耗/"..missing,W.calls.activate+#W.calls.create+W.calls.kill,0);
    end
end

local function T27_special_player_occupancy()
    for _,slot in ipairs({62,63})do
        local E=load_scripts(function(Wx)base_fill(Wx);Wx.players[slot]=make_player(slot,true);add_unit(slot,1,10,10);end);
        local x,y=E.CSF.FindFoundLocation(0);
        check("T27.1 找地避开特殊玩家单位/"..slot,x and x>=0 and (math.abs(x-10)>2 or math.abs(y-10)>2),tostring(x)..","..tostring(y));
    end
    local E=load_scripts(function(Wx)base_fill(Wx);Wx.players[63]=make_player(63,true);Wx.cities[1]=make_city(63,3,3);end);
    local ok,why=E.CSF.IsValidLocation(6,3,0);
    check("T27.2 自由城市距离边界同样拒绝",ok==false and why=="too_close",tostring(why));
    check("T27.3 自由城市四格外仍允许",E.CSF.IsValidLocation(7,3,0)==true,"distance4");
end

local function T28_city_state_turn_tasks()
    local function build(fill)
        local E = load_scripts(function(Wx)
            base_fill(Wx);
            add_envoy(10, 10);
            if fill ~= nil then fill(Wx) end
        end);
        E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0);
        HOOKS.gce();
        local _, ok, reason = E.CSF.GetLastResult();
        return E, ok, reason;
    end
    local function tasks()
        local t = W.turn_tasks[TARGET_SLOT];
        if type(t) ~= "table" then return "nil" end
        return tostring(t[1]) .. "/" .. tostring(t[2]) .. "/" .. tostring(t[3]);
    end

    -- (a) 正常：默认空任务 → 装配一次 15/6/3 → 完成；重复 Complete 不重放
    local E, ok, reason = build();
    check("T28.1 正常建邦完成", ok == true and reason == "ok", tostring(reason));
    check_eq("T28.2 默认空任务只装配一次", W.calls.init_turn_tasks, 1);
    check_eq("T28.3 装配结果为 15/6/3", tasks(), "15/6/3");
    check_eq("T28.4 首次完成发奖一次", W.reward_calls, 1);
    local again, why = E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check("T28.5 重复 Complete 直接成功", again == true and why == "ok", tostring(why));
    check_eq("T28.6 重复 Complete 不重放任务", W.calls.init_turn_tasks, 1);
    check_eq("T28.7 重复 Complete 不重发奖励", W.reward_calls, 1);

    -- (b) 桥返回 1 但静默无任务：读回不完整 → 失败、不发奖、不可重放
    E, ok, reason = build(function(Wx) Wx.init_tasks_behavior = "silent" end);
    check("T28.8 返回1但静默无任务判失败",
          ok == false and reason == "founding_ai_tasks_unconfirmed", tostring(reason));
    check_eq("T28.9 静默失败只尝试一次", W.calls.init_turn_tasks, 1);
    check_eq("T28.10 静默失败不发奖励", W.reward_calls, 0);
    check("T28.11 尝试标记先持久化",
          W.props["CSF_TurnTasksAttempted_" .. TARGET_SLOT] == true, "attempted");
    E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check_eq("T28.12 静默失败后重复不调装配", W.calls.init_turn_tasks, 1);

    -- (c) 只补部分：如实读回部分状态 → 失败，重复仍不重放
    E, ok, reason = build(function(Wx) Wx.init_tasks_behavior = "partial" end);
    check("T28.13 只补部分判失败",
          ok == false and reason == "founding_ai_tasks_unconfirmed", tostring(reason));
    check_eq("T28.14 部分结果如实读回", tasks(), "15/0/0");
    check_eq("T28.15 部分失败只装配一次", W.calls.init_turn_tasks, 1);
    E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check_eq("T28.16 部分失败重复不重放", W.calls.init_turn_tasks, 1);
    check_eq("T28.17 部分失败不发奖励", W.reward_calls, 0);

    -- (d) 装配后抛错，但读回已完整 → 按成功处理（不因抛错误判）
    E, ok, reason = build(function(Wx) Wx.init_tasks_behavior = "throw_after" end);
    check("T28.18 装配后抛错但读回完整按成功",
          ok == true and reason == "ok", tostring(reason));
    check_eq("T28.19 抛错但完整只装配一次", W.calls.init_turn_tasks, 1);
    check_eq("T28.20 抛错但完整正常发奖", W.reward_calls, 1);

    -- (e) 抛错且无状态：失败，先持久 Attempted，重复不再碰 native
    E, ok, reason = build(function(Wx) Wx.init_tasks_behavior = "throw" end);
    check("T28.21 抛错无状态判失败",
          ok == false and reason == "founding_ai_tasks_unconfirmed", tostring(reason));
    check_eq("T28.22 抛错无状态只尝试一次", W.calls.init_turn_tasks, 1);
    E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check_eq("T28.23 抛错无状态重复不重放", W.calls.init_turn_tasks, 1);
    check_eq("T28.24 抛错无状态不发奖励", W.reward_calls, 0);

    -- (f) 事先已有部分/多份任务：拒绝，绝不调用 native 覆盖
    E, ok, reason = build(function(Wx) Wx.turn_tasks[TARGET_SLOT] = {15, 0, 0} end);
    check("T28.25 事先部分拒绝且不调装配",
          ok == false and reason == "founding_ai_tasks_unconfirmed" and
          W.calls.init_turn_tasks == 0, tostring(reason));
    check_eq("T28.26 事先部分不发奖励", W.reward_calls, 0);
    E, ok, reason = build(function(Wx) Wx.turn_tasks[TARGET_SLOT] = {30, 12, 6} end);
    check("T28.27 多份任务拒绝且不调装配",
          ok == false and reason == "founding_ai_tasks_unconfirmed" and
          W.calls.init_turn_tasks == 0, tostring(reason));

    -- (g) owner 不符 / 任务读不到 / 容量超过 256：失败且不调 native
    E, ok, reason = build(function(Wx) Wx.turn_task_owner_matches = false end);
    check("T28.28 owner不符判失败且不调装配",
          ok == false and reason == "founding_ai_tasks_unconfirmed" and
          W.calls.init_turn_tasks == 0, tostring(reason));
    E, ok, reason = build(function(Wx) Wx.turn_task_read = false end);
    check("T28.29 任务读不到判失败且不调装配",
          ok == false and reason == "founding_ai_tasks_unconfirmed" and
          W.calls.init_turn_tasks == 0, tostring(reason));
    E, ok, reason = build(function(Wx) Wx.turn_task_caps[TARGET_SLOT] = {257, 256, 256} end);
    check("T28.30 过大容量判失败且不调装配",
          ok == false and reason == "founding_ai_tasks_unconfirmed" and
          W.calls.init_turn_tasks == 0, tostring(reason));

    -- (h) 旧档已有完整 15/6/3：建邦与读档恢复都不应重放装配
    E, ok, reason = build(function(Wx) Wx.turn_tasks[TARGET_SLOT] = {15, 6, 3} end);
    check("T28.31 旧档完整直接成功", ok == true and reason == "ok", tostring(reason));
    check_eq("T28.32 旧档完整不调装配", W.calls.init_turn_tasks, 0);
    W.combat[TARGET_SLOT] = 0;
    HOOKS.lsc();
    check_eq("T28.33 读档恢复完整任务不调装配", W.calls.init_turn_tasks, 0);
    check_eq("T28.34 读档恢复任务保持完整", tasks(), "15/6/3");
    check_eq("T28.35 读档恢复不重复发奖", W.reward_calls, 1);

    -- (i) 激活前缺新接口：必须 no_c6fw，且零引擎变动
    local function missing(field)
        local M = load_scripts(function(Wx) base_fill(Wx); add_envoy(10, 10); end);
        C6FW[field] = nil;
        local mok, mwhy = found(M, TARGET_CIV, 10, 10, 1001, 0);
        check("T28.36 激活前拒绝缺接口/" .. field,
              mok == false and mwhy == "no_c6fw", tostring(mwhy));
        check_eq("T28.37 缺接口零引擎变动/" .. field,
                 W.calls.activate + #W.calls.create + W.calls.kill, 0);
    end
    missing("InitializeCityStateTurnTasks");
    missing("GetPlayerSnapshot");
end

local function T29_copy_real_city_name()
    local function build(mode, missing)
        local E=load_scripts(function(Wx)
            base_fill(Wx);Wx.players[TARGET_SLOT]=nil;Wx.cfgs[TARGET_SLOT]=nil;
            Wx.cfgs[7]._civ=TARGET_CIV;Wx.cfgs[7]._leader="LEADER_MINOR_CIV_ANTANANARIVO";
            Wx.cities[1]=make_city(7,2,2);Wx.cities[1]._name="PersonalOriginal";
            Wx.closed_fixture=true;Wx.cfgs[6]=make_cfg({status=2});Wx.cfgs[6]._level=nil;
            Wx.activate_publishes_alive=true;Wx.snapshot_mode="good";
            Wx.copy_name_behavior=mode;Wx.no_city_names=missing;add_envoy(10,10);
        end);
        E.CSF.RequestFound(TARGET_CIV,10,10,1001,0);HOOKS.gce();
        local _,ok,why,slot=E.CSF.GetLastResult();
        return E,ok,why,slot;
    end
    local E,ok,why,slot=build();
    check("T29.1 副本完整建邦成功",ok==true and slot==6,tostring(why));
    local city=Cities.GetCityInPlot(10,10);
    check_eq("T29.2 真名保存本地化模板与原编号",city and city:GetName(),"{LOC_CITY_NAME_TARGET} II");
    check_eq("T29.3 不覆盖原城自定义名称",W.cities[1]:GetName(),"PersonalOriginal");
    check_eq("T29.4 新城只写名一次",W.copy_name_calls,1);
    local record=W.props.CSF_CopyCityName_6;
    check("T29.5 名称证据绑定真实城ID位置",record and record.CityID==city:GetID() and
        record.Civ==TARGET_CIV and record.X==10 and record.Y==10 and record.Suffix==" II","bound");
    city:SetName("PlayerRenamedCity");
    local calls=W.copy_name_calls;
    check("T29.6 重复完成仍成功",E.CSF.CompleteFounding(6,0)==true,"done");
    HOOKS.lsc();
    check_eq("T29.7 完成和读档不覆盖玩家后改的名",city:GetName(),"PlayerRenamedCity");
    check_eq("T29.8 完成和读档不再写城市名",W.copy_name_calls,calls);

    for _,mode in ipairs({"silent","throw"})do
        E,ok,why,slot=build(mode);
        check("T29.9 改名无实际效果拒绝成功/"..mode,
            ok==false and why=="copy_city_name_unconfirmed",tostring(why));
        check("T29.10 部分建城失败持久隔离/"..mode,W.props.CSF_IsolatedSlot_6~=nil,"isolated");
        check_eq("T29.11 命名失败不发使者/"..mode,W.reward_calls,0);
        check_eq("T29.12 不删除已建真实城市/"..mode,#live_cities(6),1);
    end
    E,ok,why,slot=build("throw_after");
    check("T29.13 写后抛错以准确读回确认",ok==true,tostring(why));
    check_eq("T29.14 写后抛错真名正确",Cities.GetCityInPlot(10,10):GetName(),"{LOC_CITY_NAME_TARGET} II");
    E,ok,why,slot=build(nil,true);
    check("T29.15 缺本源城名提前拒绝",ok==false and why=="copy_city_name_unavailable",tostring(why));
    check_eq("T29.16 缺城名不激活不建城不消费",W.calls.activate+#W.calls.create+W.calls.kill,0);

    E=load_scripts(function(Wx)base_fill(Wx);add_envoy(10,10);end);
    E.CSF.RequestFound(TARGET_CIV,10,10,1001,0);HOOKS.gce();
    check_eq("T29.17 非副本路径不改城市名",W.copy_name_calls,nil);
end

-- T30：容量边界。0..60 必须有真实身份/存活玩家，不能拿"全 nil + status2"
-- 冒充占满；10/20 是混合的隔离空槽，61 是唯一合法空关闭槽，62/63 保留特殊身份。
local function T30_capacity_last_closed_slot()
    local function snapshot()
        local t = {};
        for i = 0, 63 do
            local c, p = W.cfgs[i], W.players[i];
            t[i] = {
                civ = c and c._civ or nil,
                leader = c and c._leader or nil,
                level = c and c._level or nil,
                status = c and c._status or nil,
                alive = p ~= nil and p._alive == true,
                cities = #live_cities(i),
            };
        end
        return t;
    end
    local function same(a, b, skip61)
        for i = 0, 63 do
            if not (skip61 and i == 61) then
                local x, y = a[i], b[i];
                if x.civ ~= y.civ or x.leader ~= y.leader or x.level ~= y.level
                   or x.status ~= y.status or x.alive ~= y.alive
                   or x.cities ~= y.cities then
                    return false, i;
                end
            end
        end
        return true, nil;
    end
    local function fill(Wx)
        base_fill(Wx);
        Wx.players[TARGET_SLOT] = nil; Wx.cfgs[TARGET_SLOT] = nil;
        -- 槽7 = 原文明真实城市：让 hasIdentity=true，强制走副本路径
        Wx.players[7] = make_player(7, true);
        Wx.cfgs[7] = make_cfg({ civ = TARGET_CIV, leader = "LEADER_MINOR_CIV_ANTANANARIVO",
                                level = "CIVILIZATION_LEVEL_CITY_STATE", status = 1, color = 3 });
        Wx.cities[#Wx.cities + 1] = make_city(7, 2, 2);
        Wx.cities[#Wx.cities]._name = "PersonalOriginal";
        Wx.alive_minors = { 7 };
        Wx.closed_fixture = true;
        Wx.activate_publishes_alive = true;
        Wx.snapshot_mode = "good";
        -- 0..60：除 7/10/20 外全部已有身份且存活。存活状态使副本扫描
        -- （要求 alive~=true）无法把它们当 victim；它们也不在 alive_minors。
        for i = 1, 60 do
            if i ~= 7 and i ~= 10 and i ~= 20 then
                Wx.cfgs[i] = make_cfg({ civ = "CIVILIZATION_CAP_" .. tostring(i),
                                        leader = "LEADER_MINOR_CIV_CAP_" .. tostring(i),
                                        level = "CIVILIZATION_LEVEL_CITY_STATE",
                                        status = 5, color = 3 });
                Wx.players[i] = make_player(i, true);
            end
        end
        -- 混合隔离：两个 status=2、无身份的空槽，必须被跳过而不是复用。
        Wx.cfgs[10] = make_cfg({ status = 2 }); Wx.cfgs[10]._level = nil;
        Wx.cfgs[20] = make_cfg({ status = 2 }); Wx.cfgs[20]._level = nil;
        Wx.props.CSF_IsolatedSlot_10 = "old_failure";
        Wx.props.CSF_IsolatedSlot_20 = "old_failure";
        -- 61：唯一合法空关闭槽
        Wx.cfgs[61] = make_cfg({ status = 2 }); Wx.cfgs[61]._level = nil;
        -- 62/63：正式特殊身份，不得被选择或改动
        Wx.cfgs[62] = make_cfg({ civ = "CIVILIZATION_BARBARIAN", leader = "LEADER_BARBARIAN",
                                 level = "CIVILIZATION_LEVEL_BARBARIAN", status = 1, color = nil });
        Wx.players[62] = make_player(62, true);
        Wx.cfgs[63] = make_cfg({ civ = "CIVILIZATION_FREE_CITY", leader = "LEADER_FREE_CITY",
                                 level = "CIVILIZATION_LEVEL_FREE_CITY", status = 1, color = nil });
        Wx.players[63] = make_player(63, true);
        add_envoy(10, 10);
    end

    local E = load_scripts(fill);
    local before = snapshot();
    E.CSF.RequestFound(TARGET_CIV, 10, 10, 1001, 0); HOOKS.gce();
    local _, ok, why, slot = E.CSF.GetLastResult();
    check("T30.1 原文明副本选中最后一个合法空槽61",
          ok == true and slot == 61, tostring(why) .. " slot=" .. tostring(slot));
    check("T30.2 混合隔离槽10/20未被复用",
          W.props.CSF_IsolatedSlot_10 ~= nil and W.props.CSF_IsolatedSlot_20 ~= nil,
          "isolated");
    check_eq("T30.3 只登记61", W.prepare_closed_calls, 1);
    check_eq("T30.4 只激活一次", W.calls.activate, 1);
    check_eq("T30.5 只建城一次", #W.calls.create, 1);
    check_eq("T30.6 只装配回合任务一次", W.calls.init_turn_tasks, 1);
    check_eq("T30.7 只发布能力一次", W.publish_ready_calls, 1);
    check_eq("T30.8 只消耗一名使节", W.calls.kill, 1);
    check_eq("T30.9 只发一次建邦使者奖励", W.reward_calls, 1);
    check_eq("T30.10 61有唯一真实城市", #live_cities(61), 1);
    check_eq("T30.11 61身份正确", W.cfgs[61]._civ, TARGET_CIV);
    check_eq("T30.12 61原生槽状态已转为活", C6FW.GetNativeSlotStatus(61), 1);
    local same_after, bad = same(before, snapshot(), true);
    check("T30.13 除61外0..60与62/63身份/存活/城市不变",
          same_after == true, "slot=" .. tostring(bad));
    local city61 = Cities.GetCityInPlot(10, 10);
    check_eq("T30.14 副本名保存模板与后缀",
            city61 and city61:GetName(), "{LOC_CITY_NAME_TARGET} II");
    check_eq("T30.15 原城自定义名不被覆盖", W.cities[1]:GetName(), "PersonalOriginal");

    -- 满容量：61 已被占用，下一回合的新合法请求必须 no_free_slot。
    local act_before, cre_before = W.calls.activate, #W.calls.create;
    local before_full = snapshot();
    W.turn = 11;
    local envoy2 = add_envoy(15, 15);
    E.CSF.RequestFound(TARGET_CIV, 15, 15, envoy2:GetID(), 0, 1002); HOOKS.gce();
    local _, ok2, why2, slot2 = E.CSF.GetLastResult();
    check("T30.16 满槽后新请求返回no_free_slot",
          ok2 == false and why2 == "no_free_slot", tostring(why2));
    check_eq("T30.17 满槽失败返回非槽哨兵-1", slot2, -1);
    check_eq("T30.18 满槽不再激活/建城",
            W.calls.activate + #W.calls.create, act_before + cre_before);
    check_eq("T30.19 满槽不再消耗使节", W.calls.kill, 1);
    check("T30.20 新使节保留", envoy2._dead ~= true, "retained");
    local same_full, bad2 = same(before_full, snapshot());
    check("T30.21 满槽拒绝不改任何身份/特殊槽/城市",
          same_full == true, "slot=" .. tostring(bad2));
    check_eq("T30.22 61城市仍在", #live_cities(61), 1);
    check_eq("T30.23 始终不走AddPlayer/UninitializePlayer",
            W.calls.add_player + #W.calls.uninit, 0);

    DB.ConfigurationQuery = function() return {{CivilizationType = TARGET_CIV, Name = "Target"}} end;
    local choices = E.CSF.GetFoundableCityStates(0);
    check("T30.24 满槽候选明确报告容量耗尽",
          #choices == 1 and choices[1].Mode == "unavailable" and
          choices[1].UnavailableReason == "no_free_slot", "capacity reason");
    local publish = C6FW.PublishCityStateReady;
    C6FW.PublishCityStateReady = nil;
    choices = E.CSF.GetFoundableCityStates(0);
    check("T30.25 缺桥不能冒充容量耗尽",
          #choices == 1 and choices[1].UnavailableReason == "native_unavailable", "dependency reason");
    C6FW.PublishCityStateReady = publish;

    -- Defensive fixture only: even malformed metadata cannot make the two
    -- reserved IDs allocatable. This is not a real-game slot configuration.
    for i = 62, 63 do
        W.cfgs[i]._level = "CIVILIZATION_LEVEL_CITY_STATE";
        W.cfgs[i]._status = 5;
        W.players[i]._alive = false;
    end
    W.turn = 12;
    E.CSF.RequestFound(TARGET_CIV, 15, 15, envoy2:GetID(), 0, 1003); HOOKS.gce();
    local _, reserved_ok, reserved_reason = E.CSF.GetLastResult();
    check("T30.26 特殊槽即使元数据损坏也不可分配",
          reserved_ok == false and reserved_reason == "no_free_slot" and
          W.calls.activate == act_before and #W.calls.create == cre_before and
          W.calls.kill == 1, tostring(reserved_reason));
end

-- T31: 旧档记录缺 StockBefore 时，CompleteFounding 必须在任何发奖动作前拒绝。
-- 当前实现会先 GiveFreeTokenToPlayer，再在库存比较处失败；本用例先跑出现状。
local function T31_legacy_record_missing_stock_before()
    local sKey = "CSF_Founding_" .. tostring(TARGET_SLOT);
    local function fill(Wx)
        base_fill(Wx);
        Wx.cities[#Wx.cities + 1] = make_city(TARGET_SLOT, 10, 10);
        -- 先有 1 个使者；一次奖励后达到历史 RewardTarget=2，排除“奖励没到账”干扰。
        Wx.tokens[key2(TARGET_SLOT, 0)] = 1;
        Wx.stock[0] = 0;
        Wx.props[sKey] = {
            Owner = 0, X = 10, Y = 10,
            RewardTarget = 2,
            -- 关键：旧记录没有 StockBefore；Done=false，RewardAttempted 未写。
        };
    end

    local E = load_scripts(fill);
    local city = W.cities[1];
    local nameBefore = city:GetName();
    local ok, why = E.CSF.CompleteFounding(TARGET_SLOT, 0);
    check("T31.1 缺StockBefore的未完成记录必须拒绝", ok == false, tostring(why));
    check("T31.1b 拒绝必须发生在发奖前，而不是发奖后才发现库存不符",
          tostring(why) ~= "founding_envoy_spent_stock", tostring(why));
    check_eq("T31.2 发奖前拒绝：不得调用GiveFreeTokenToPlayer", W.reward_calls, 0);
    check("T31.3 不得写Done", W.props[sKey].Done ~= true,
          "Done=" .. tostring(W.props[sKey].Done));
    check("T31.4 不得写RewardAttempted", W.props[sKey].RewardAttempted ~= true,
          "RewardAttempted=" .. tostring(W.props[sKey].RewardAttempted));
    check_eq("T31.5 已有城市仍在且数量不变", #live_cities(TARGET_SLOT), 1);
    check_eq("T31.6 已有城市名不变", city:GetName(), nameBefore);

    -- 历史已完成记录：Done=true 且缺 StockBefore，读档/CompleteFounding 不得额外奖励。
    local E2 = load_scripts(function(Wx)
        fill(Wx);
        Wx.props[sKey].Done = true;
    end);
    local ok2, why2 = E2.CSF.CompleteFounding(TARGET_SLOT, 0);
    check("T31.7 Done历史记录缺StockBefore仍返回ok", ok2 == true, tostring(why2));
    check_eq("T31.8 Done历史记录不额外奖励", W.reward_calls, 0);
    check_eq("T31.9 Done历史记录城市数量不变", #live_cities(TARGET_SLOT), 1);
end

local TESTS = {
    { "T1_开局LoadScreenClose无操作", T1_startup_noop },
    { "T2_非法地块不激活不消耗", T2_invalid_plot },
    { "T3_原生激活失败如实报错", T3_activate_failure },
    { "T3b_SetAlive返回0判失败并隔离", T3b_setalive_failure },
    { "T3e_原生已发布alive不重复SetAlive", T3e_native_activate_already_published_alive },
    { "T3f_原生快照坏列表拒绝成功", T3f_native_snapshot_rejects_bad_lists },
    { "T3g_原生槽位状态交叉核对", T3g_native_status_crosscheck_rejects_wrong_state },
    { "T3c_补色失败不再被忽略", T3c_no_color },
    { "T3d_部分初始化后失败保守隔离", T3d_partial_activate_failure },
    { "T4_Create抛异常判失败", T4_create_threw },
    { "T5_静默0城判失败", T5_silent_zero_city },
    { "T6_别处有城目标格没城判失败", T6_city_elsewhere_not_at_target },
    { "T7_队列重复请求与重入", T7_queue_duplicate_and_reentrancy },
    { "T8_失败不烧回合且跳过隔离槽", T8_failure_does_not_burn_turn },
    { "T9_成功且只提交一次", T9_success_once },
    { "T10_隔离槽不再被挑中", T10_isolated_slot_not_picked },
    { "T11_FoundCityState目标格取证", T11_found_city_state_target_check },
    { "T12_槽位状态未生效判失败", T12_status_gate },
    { "T13_ForceReserve已是无操作", T13_force_reserve_disabled },
    { "T14_布尔false不算合法颜色", T14_color_false_not_valid },
    { "T15_状态读不到判失败", T15_status_unreadable },
    { "T16_等级不对判失败", T16_level_wrong },
    { "T17_缺少依赖不隔离干净槽", T17_missing_native_does_not_quarantine },
    { "T18_接触与免费奖励验收", T18_founding_contact_and_reward },
    { "T19_零开局空槽登记与失败守卫", T19_closed_identity },
    { "T20_真实城防与旧档恢复", T20_defense_acceptance },
    { "T21_同文明空槽副本与失败隔离", T21_duplicate_closed_slot },
    { "T22_原生名称与旧档恢复", T22_identity_text_acceptance },
    { "T23_官方通知与能力实例验收", T23_native_ability_acceptance },
    { "T24_原生操作防重与单位校验", T24_native_operation_and_validation },
    { "T25_距离边界与隔离身份", T25_distance_and_isolated_identity },
    { "T26_发奖历史与旧桥前置守卫", T26_reward_history_and_bridge_preflight },
    { "T27_特殊玩家占位与城市间距", T27_special_player_occupancy },
    { "T28_城邦回合任务装配与读回", T28_city_state_turn_tasks },
    { "T29_副本真实城市名与玩家改名保护", T29_copy_real_city_name },
    { "T30_容量边界61与满槽拒绝", T30_capacity_last_closed_slot },
    { "T31_旧记录缺StockBefore的发奖前拒绝", T31_legacy_record_missing_stock_before },
};

local n_fail = 0;
for _, kTest in ipairs(TESTS) do
    local sName, fBody = kTest[1], kTest[2];
    local okRun, err = pcall(fBody);
    if not okRun then
        check(sName .. "/夹具自身异常", false, tostring(err));
    end
end

for _, r in ipairs(RESULTS) do
    if not r.ok then n_fail = n_fail + 1 end
    -- 细节里可能带换行（日志片段）—— 必须压成一行，否则驱动脚本无法按行解析
    local sDetail = (tostring(r.detail):gsub("[\r\n]+", " ⏎ "));
    real_print("RESULT|" .. r.name .. "|" .. (r.ok and "PASS" or "FAIL") .. "|" .. sDetail);
end
real_print("TOTAL|" .. tostring(#RESULTS));
real_print("FAILED|" .. tostring(n_fail));
