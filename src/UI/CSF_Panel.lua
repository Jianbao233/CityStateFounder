-- ===========================================================================
-- CityStateFounder / 城邦缔造者 — 城邦选择面板（InGame 上下文）
-- 区段：InGameActions > AddUserInterfaces（Context=InGame）+ ImportFiles
--
-- 数据来源：ExposedMembers.CSF.GetDormantCityStates()
--   → 返回【本局休眠中的城邦】（= 预留槽位），每项含
--     PlayerID / Civ / Leader / Name / Icon / Category / Bonus / BonusXP1 / BonusXP2
--   为什么不列全池：预留城邦的身份在地图生成时就固定了，运行时改不了（T-65）
--
-- 架构约束：
--   - 建城在 GameCore（ExposedMembers.CSF.FoundCityState）
--   - 「缔造者优势 +1 使者」必须在本 UI 上下文做，因为要用
--     UI.RequestPlayerOperation + PlayerOperations.GIVE_INFLUENCE_TOKEN
--     （依据 Base/Assets/UI/PartialScreens/CityStates.lua:755-760）
-- ===========================================================================

include("InstanceManager");

-- ⭐ 旗标颜色兜底（2026-10-04）
--   本上下文（InGame）里 UI 表可用，所以在这里包装 UI.GetPlayerColors。
--   ⚠️ 千万不要用 ReplaceUIScript 去替换 CityBannerManager —— 那会连带旗标的
--      显示/隐藏逻辑一起替换掉，结果是"不崩但旗标不显示"（已踩两次）。
--   顺序：先 CopyRegistry（提供 CSF_GetCopySource），再 BannerColorFix。
include("CSF_CopyRegistry");

print("[CSF] CSF_Panel.lua loading (InGame context)");

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local m_EntryIM        = nil;    -- 列表项 InstanceManager
local m_kDormant       = {};     -- 当前可选的城邦（混合方案：全部池 + 本局休眠标记）
local m_sSelectedCiv   = nil;    -- 选中的【文明】类型（不是玩家 ID）
-- ⚠️ 只保存【纯数字】，不保存单位对象：
--    Civ6 每个 UI context 有独立 Lua state，userdata 跨 context 会失效。
local m_iTargetX       = nil;    -- 使节所在 X
local m_iTargetY       = nil;    -- 使节所在 Y
local m_iTargetUnitID  = nil;    -- 使节的单位 ID（GameCore 侧用来精确删除它）
local m_iTargetOwnerID = nil;    -- 使节的拥有者玩家 ID
local g_CSFHint        = nil;    -- 面板的提示 Label（结果回传时更新它）
local m_bWaiting       = false;  -- 已下单、等待 GameCore 执行结果
local m_iSeenSeq       = nil;    -- 已处理过的结果序号（轮询兜底去重用）
local m_bHandled       = false;  -- 本次下单的结果是否已处理（两条通道去重，防止重复给使者）

-- ---------------------------------------------------------------------------
-- ⭐ 接收 GameCore 的建邦结果（跨 VM 通信）
--    GameCore 侧在游戏事件里执行完建邦后，用 GameEvents.CSF_FoundResult 广播。
--
-- ⚠️⚠️ 必须做存在性守卫！
--    实测：某些 UI 上下文里 `GameEvents` 是 **nil**（探针在 InGame 状态读到
--    `type(GameEvents) == "nil"`）。若不加守卫，顶层直接索引会**让整个面板加载失败**。
--    另外 `.CSF_FoundResult` 这个事件在 GameCore 首次 Raise 之前可能还不存在，
--    所以 .Add 也要包在 pcall 里。
-- ---------------------------------------------------------------------------
local function CSF_RegisterResultListener()
    if GameEvents == nil then
        print("[CSF] WARN: GameEvents 在本上下文为 nil，结果回传不可用（不影响建邦本身）");
        return;
    end
    local ok = pcall(function()
        GameEvents.CSF_FoundResult.Add(function(bOk, sReason, iCsPlayer, iX, iY)
            print("[CSF] GameEvents.CSF_FoundResult: ok=" .. tostring(bOk) ..
                  " reason=" .. tostring(sReason) .. " player=" .. tostring(iCsPlayer));
            CSF_OnFoundResult(bOk, sReason, iCsPlayer);
        end);
    end);
    if ok then
        print("[CSF] 已注册 GameEvents.CSF_FoundResult 结果监听");
    else
        print("[CSF] WARN: GameEvents.CSF_FoundResult 注册失败（事件可能尚未创建）");
    end
end
CSF_RegisterResultListener();

-- ---------------------------------------------------------------------------
-- 工具
-- ---------------------------------------------------------------------------
local function CSF_Safe(f, ...)
    local ok, v = pcall(f, ...);
    if ok then return v end;
    return nil;
end

local function CSF_Loc(sKey)
    if sKey == nil then return "" end
    local s = CSF_Safe(function() return Locale.Lookup(sKey) end);
    return s or sKey;
end

-- 按规则集选宗主加成文本（照抄 FrontEnd/CityStatePicker.lua:94-111 的逻辑）
local function CSF_PickBonusText(kEntry)
    local bXP2 = CSF_Safe(function() return IsExpansion2Enabled() end);
    local bXP1 = CSF_Safe(function() return IsExpansion1Enabled() end);

    if kEntry.BonusXP2 ~= nil and bXP2 == true then
        return CSF_Loc(kEntry.BonusXP2);
    elseif kEntry.BonusXP1 ~= nil and bXP1 == true then
        return CSF_Loc(kEntry.BonusXP1);
    end
    return CSF_Loc(kEntry.Bonus);
end

local function CSF_CategoryLoc(sCat)
    -- 类别显示：官方键是 LOC_CITY_STATES_TYPE_<类别>（不是 LOC_CITY_STATE_CATEGORY_*）
    --   实测 CityStates.CityStateCategory 的取值为
    --   TRADE / INDUSTRIAL / MILITARISTIC / SCIENTIFIC / RELIGIOUS / CULTURAL
    if sCat == nil then return "" end
    local sKey = "LOC_CITY_STATES_TYPE_" .. tostring(sCat);
    local s = CSF_Safe(function() return Locale.Lookup(sKey) end);
    if s == nil or s == "" or s == sKey then
        return "";                 -- 查不到就不显示，别把原始键名摆出来
    end
    return s;
end

-- ---------------------------------------------------------------------------
-- 面板开关
-- ---------------------------------------------------------------------------
function CSF_IsOpen()
    return not Controls.CSFRoot:IsHidden();
end

function CSF_Close()
    Controls.CSFRoot:SetHide(true);
    -- 官方关闭方式（与 QueuePopup 配对）
    CSF_Safe(function() UIManager:DequeuePopup(ContextPtr) end);
    m_sSelectedCiv   = nil;
    m_iTargetX       = nil;
    m_iTargetY       = nil;
    m_iTargetUnitID  = nil;
    m_iTargetOwnerID = nil;
end

-- ---------------------------------------------------------------------------
-- 出场动画：**已刻意移除**
--   官方弹窗（Base/Assets/UI/Popups/PopupDialog.lua:344-349）会显式调
--     SetToBeginning() + Play()
--   但实测本面板在脚本打开时动画**不会推进**，会停在 Begin 位移上：
--     · SlideAnim 停在 Begin="0,-24" → 面板永久偏上 24px（用户反馈"太靠近屏幕边缘"）
--     · AlphaAnim 停在 AlphaBegin="0" → 整个面板透明（更不可接受）
--   → 结论：**不做出场动画，换取精确居中**。`lint.js` 的 no-anim WARN 是有意保留的。
-- ---------------------------------------------------------------------------

function CSF_Open()
    -- ⚠️ 用 UIManager:QueuePopup 显示（官方 popup 面板的标准做法，
    --    见 DiplomacyActionView / ReligionScreen / Options 等）。
    --    只靠 SetHide(false) 在某些情况下面板不会真正显示到前台。
    CSF_Safe(function() UIManager:QueuePopup(ContextPtr, PopupPriority.Current) end);
    Controls.CSFRoot:SetHide(false);
    g_CSFHint  = Controls.CSFHint;    -- 记住提示 Label，供结果回传时更新
    m_bWaiting = false;
    m_bHandled = false;              -- 每次打开面板重置去重标记
    CSF_Refresh();
end

-- ---------------------------------------------------------------------------
-- 列表刷新
-- ---------------------------------------------------------------------------
function CSF_Refresh()
    m_EntryIM:ResetInstances();
    m_kDormant = {};
    m_sSelectedCiv = nil;
    Controls.CSFSelectedName:SetText("");
    Controls.CSFSelectedBonus:SetText("");

    -- 取【全部可建立城邦】（混合方案：优先复用本局休眠玩家，兜底动态创建）
    local fGet = nil;
    if ExposedMembers ~= nil and ExposedMembers.CSF ~= nil then
        fGet = ExposedMembers.CSF.GetFoundableCityStates;
    end
    if fGet == nil then
        print("[CSF] ExposedMembers.CSF.GetFoundableCityStates 不可用");
        Controls.CSFHint:SetText(CSF_Loc("LOC_CSF_PANEL_NO_POOL"));
        return;
    end

    local tAll = CSF_Safe(fGet) or {};

    -- ⭐ 只列【真正能建】的城邦（Mode == "reuse"）。
    --   为什么要过滤：本局只有 N 个城邦（N 由开局设置决定），
    --   其余 48-N 个在运行时建不出「完全可用」的城邦（引擎不支持，见 T-115/T-118）。
    --   列出来却点不了只会让人困惑，所以直接只显示可用的，并提示如何获得更多。
    -- ⭐ 只列【真正能建】的城邦。
    --
    --   2026-10-06 更新：现在有**两条**可用路径，都要列：
    --     · "reuse" —— 本局已有同文明休眠玩家 → 直接复用
    --     · "slot"  —— ★ 该文明有【自己的未激活预注册槽】→ 激活它
    --                  引擎开局把全部 54 个城邦文明都预注册成槽（status=5），
    --                  所以这条路能建**全部 54 个里的任意一个**，且【不改文明】→ 不崩。
    --
    --   仍然不列 "retarget" / "dynamic" / "unavailable"：
    --   前者改文明（实测挂起），后者是半成品 —— 列出来却点不了只会让人困惑。
    local tList = {};
    for _, kEntry in ipairs(tAll) do
        if kEntry.Mode == "reuse" or kEntry.Mode == "slot" then
            tList[#tList + 1] = kEntry;
        end
    end
    m_kDormant = tList;

    if #tList == 0 then
        Controls.CSFHint:SetText(CSF_Loc("LOC_CSF_PANEL_NO_POOL"));
        return;
    end
    -- ⭐ 先检查【当前位置能不能建】，让玩家点之前就知道（避免白点一次）
    local fValid = (ExposedMembers ~= nil and ExposedMembers.CSF ~= nil)
                   and ExposedMembers.CSF.IsValidLocation or nil;
    local sSpotMsg = "";
    if fValid ~= nil and m_iTargetX ~= nil and m_iTargetY ~= nil then
        local ok, bOk, sWhy = pcall(fValid, m_iTargetX, m_iTargetY, m_iTargetOwnerID);
        if ok and bOk ~= true then
            sSpotMsg = "  ⚠️ " .. CSF_ReasonText(sWhy);
            print("[CSF] panel: 当前位置不可建邦 -> " .. tostring(sWhy));
        end
    end

    -- 提示里带上"可用 / 本局总数"，让玩家知道还能不能更多
    --   ⭐ 面板【只列本局真实存在的城邦】——因为只有它们能被引擎正确创建。
    --   ⚠️⚠️ 这里必须用【本局城邦数】，不能用【城邦池大小】（T-145 修正）：
    --      池子固定 48 个（Expansion2CityStates 域），而本局只有开局设置的数量
    --      （标准 12 / 巨大 18）。曾经误用池子大小 → 显示"本局共 48 个城邦"，
    --      玩家会以为有 48 个可用，实际只能建 7 个，非常困惑。
    local iGameTotal = #tAll;    -- 兜底：拿不到统计时退回旧行为
    local fStats = (ExposedMembers ~= nil and ExposedMembers.CSF ~= nil)
                   and ExposedMembers.CSF.GetGameCityStateStats or nil;
    if fStats ~= nil then
        local okS, kStats = pcall(fStats);
        if okS and type(kStats) == "table" and kStats.total ~= nil then
            iGameTotal = kStats.total;
            print("[CSF] panel: 本局城邦统计 total=" .. tostring(kStats.total) ..
                  " dormant=" .. tostring(kStats.dormant) ..
                  " active=" .. tostring(kStats.active) ..
                  " pending=" .. tostring(kStats.pending) ..
                  " pool=" .. tostring(kStats.pool));
        end
    end

    Controls.CSFHint:SetText(
        CSF_Loc("LOC_CSF_PANEL_HINT") .. "[NEWLINE]" ..
        CSF_Loc("LOC_CSF_PANEL_COUNT_PRE") .. " " .. tostring(#tList) .. " " ..
        CSF_Loc("LOC_CSF_PANEL_COUNT_MID") .. " " .. tostring(iGameTotal) .. " " ..
        CSF_Loc("LOC_CSF_PANEL_COUNT_SUF") ..
        (sSpotMsg ~= "" and ("[NEWLINE]" .. sSpotMsg) or ""));
    print("[CSF] panel: 本局可用城邦 " .. tostring(#tList) ..
          " 个（本局城邦共 " .. tostring(iGameTotal) .. " 个）");

    local iReusable = 0;
    for _, kEntry in ipairs(tList) do
        local kInst = m_EntryIM:GetInstance();

        kInst.CSFEntryIcon:SetIcon(kEntry.Icon or "ICON_CIVILIZATION_AMSTERDAM");
        kInst.CSFEntryName:SetText(CSF_Loc(kEntry.Name));
        kInst.CSFEntryCategory:SetText(CSF_CategoryLoc(kEntry.Category));

        -- 能列出来的都是 reuse（机制完整），不再需要角标
        iReusable = iReusable + 1;
        kInst.CSFEntryStatus:SetText("");

        -- 加成摘要（截断显示，完整文本在下方详情区）
        kInst.CSFEntryBonus:SetText(CSF_PickBonusText(kEntry));

        local sCiv = kEntry.Civ;
        kInst.CSFEntryButton:RegisterCallback(Mouse.eLClick, function()
            CSF_SelectEntry(sCiv);
        end);
    end

    print("[CSF] panel: " .. tostring(#tList) .. " 个可选城邦，其中 " ..
          tostring(iReusable) .. " 个本局已有休眠玩家（机制完整）");

    Controls.CSFCityStateStack:CalculateSize();
    Controls.CSFCityStateScroll:CalculateSize();
end

function CSF_SelectEntry(sCiv)
    m_sSelectedCiv = sCiv;
    for _, kEntry in ipairs(m_kDormant) do
        if kEntry.Civ == sCiv then
            Controls.CSFSelectedName:SetText(CSF_Loc(kEntry.Name));
            local sBonus = CSF_PickBonusText(kEntry);
            if not kEntry.CanReceiveInfluence then
                sBonus = sBonus .. "[NEWLINE][COLOR:255,180,120,255]" ..
                         CSF_Loc("LOC_CSF_PANEL_DYNAMIC_WARN") .. "[ENDCOLOR]";
            end
            Controls.CSFSelectedBonus:SetText(sBonus);
            break;
        end
    end
end

-- ---------------------------------------------------------------------------
-- 缔造者优势：给建立者 1 个使者
--   依据 Base/Assets/UI/PartialScreens/CityStates.lua:755-760
-- ---------------------------------------------------------------------------
local function CSF_GiveFounderEnvoy(iCityStatePlayerID)
    local iLocal = CSF_Safe(function() return Game.GetLocalPlayer() end);
    if iLocal == nil or iLocal < 0 then return false end

    local kParams = {};
    kParams[PlayerOperations.PARAM_PLAYER_ONE] = iCityStatePlayerID;

    local bOk = pcall(function()
        UI.RequestPlayerOperation(iLocal, PlayerOperations.GIVE_INFLUENCE_TOKEN, kParams);
    end);
    print("[CSF] founder envoy -> city-state " .. tostring(iCityStatePlayerID) .. " ok=" .. tostring(bOk));
    return bOk;
end

-- ---------------------------------------------------------------------------
-- 确认建立
--
-- ⚠️ 为什么要"下单"而不是"直接建"（实测教训 T-94）：
--    `AddPlayer` / `SetPlayerLeader` / `Cities:Create` 是改变引擎结构的重操作。
--    如果直接在 **UI 按钮回调的调用栈内**执行，引擎此刻正在遍历相关数据，
--    结构被改动 → **崩溃弹窗**（实测：日志停在 `dynamic: created player 54` 之后就断了）。
--    对照实验：同样的函数在 tuner 上下文、在 `InGame` UI 状态里单独调用都正常。
--    → 所以 UI 只把请求交给 GameCore 排队，由 GameCore 在游戏事件里执行。
-- ---------------------------------------------------------------------------
function CSF_OnConfirm()
    if m_sSelectedCiv == nil then
        print("[CSF] 未选择城邦");
        return;
    end
    if m_iTargetX == nil or m_iTargetY == nil or m_iTargetX < 0 or m_iTargetY < 0 then
        print("[CSF] 目标坐标无效");
        return;
    end
    local iX, iY = m_iTargetX, m_iTargetY;
    local iUnitID  = m_iTargetUnitID;
    local iOwnerID = m_iTargetOwnerID;

    -- 【只下单，不执行】—— 队列由 GameCore 在游戏事件里消费
    local fReq = (ExposedMembers ~= nil and ExposedMembers.CSF ~= nil)
                 and ExposedMembers.CSF.RequestFound or nil;
    if fReq == nil then
        print("[CSF] RequestFound 不可用");
        return;
    end

    local bQueued = fReq(m_sSelectedCiv, iX, iY, iUnitID, iOwnerID);
    if bQueued ~= true then
        print("[CSF] 下单失败");
        Controls.CSFHint:SetText(CSF_Loc("LOC_CSF_PANEL_INVALID_LOCATION"));
        return;
    end

    print("[CSF] 已下单：" .. tostring(m_sSelectedCiv) .. " @(" ..
          tostring(iX) .. "," .. tostring(iY) .. ")，等待 GameCore 处理");
    -- ⚠️ 不要立刻关面板：执行是【延后】的，关了就没地方显示结果了。
    --    显示"处理中"，等 GameEvents.CSF_FoundResult 回来再关（见 CSF_OnFoundResult）。
    Controls.CSFHint:SetText(CSF_Loc("LOC_CSF_PANEL_PENDING"));
    g_CSFHint = Controls.CSFHint;
    m_bWaiting = true;
end

-- 接收 GameCore 的执行结果（跨 VM：GameCore 用 GameEvents 广播）
--
-- ⚠️ 结果有【两条通道】：GameEvents 广播 + UI 轮询兜底（因为某些上下文里 GameEvents 为 nil）。
--    两条都可能触发 → 必须去重，否则 `CSF_GiveFounderEnvoy` 会**重复给使者**。
function CSF_OnFoundResult(bOk, sReason, iCsPlayer)
    if m_bHandled then
        print("[CSF] 结果已处理过，忽略重复回调: ok=" .. tostring(bOk) ..
              " reason=" .. tostring(sReason));
        return;
    end
    m_bHandled = true;
    m_bWaiting = false;
    print("[CSF] 建邦结果: ok=" .. tostring(bOk) .. " reason=" .. tostring(sReason) ..
          " player=" .. tostring(iCsPlayer));
    if bOk == true then
        if iCsPlayer ~= nil and iCsPlayer >= 0 then
            CSF_GiveFounderEnvoy(iCsPlayer);
        end
        print("[CSF] 城邦已建立，player=" .. tostring(iCsPlayer));
        CSF_Close();
    else
        -- 把机器错误码翻译成玩家能看懂的话
        if g_CSFHint ~= nil then
            g_CSFHint:SetText(CSF_Loc("LOC_CSF_PANEL_FOUND_FAIL") .. " " ..
                              CSF_ReasonText(sReason));
        end
    end
end

-- 错误码 → 玩家可读文本
function CSF_ReasonText(sReason)
    local kMap = {
        bad_args          = "LOC_CSF_REASON_BAD_ARGS",
        no_plot           = "LOC_CSF_REASON_NO_PLOT",
        water             = "LOC_CSF_REASON_WATER",
        owned_own         = "LOC_CSF_REASON_OWNED_OWN",
        owned_by_other    = "LOC_CSF_REASON_OWNED_OTHER",
        owned_not_cleared = "LOC_CSF_REASON_OWNED_NOT_CLEARED",
        too_close         = "LOC_CSF_REASON_TOO_CLOSE",
        map_edge          = "LOC_CSF_REASON_MAP_EDGE",
        too_little_land   = "LOC_CSF_REASON_LITTLE_LAND",
        no_free_slot      = "LOC_CSF_REASON_NO_SLOT",
        no_leader         = "LOC_CSF_REASON_NO_LEADER",
        no_worldbuilder   = "LOC_CSF_REASON_NO_WB",
        silent_fail       = "LOC_CSF_REASON_SILENT",
        create_threw      = "LOC_CSF_REASON_CREATE_THREW",
        dynamic_disabled  = "LOC_CSF_REASON_DISABLED",
        threw             = "LOC_CSF_REASON_THREW",
    };
    local sKey = kMap[tostring(sReason)];
    if sKey == nil then
        return tostring(sReason);       -- 未知原因就原样显示
    end
    local sText = CSF_Loc(sKey);
    if sText == sKey then
        return tostring(sReason);       -- 没查到本地化就退回错误码
    end
    return sText;
end

-- ---------------------------------------------------------------------------
-- 入口：由 UnitPanel 补丁通过 LuaEvents 调用
--   参数全是【纯数字】：坐标 + 单位 ID + 拥有者 ID
--   （跨 context 不能传 userdata 单位对象，否则对方拿到 nil）
-- ---------------------------------------------------------------------------
function CSF_OpenAt(iX, iY, iUnitID, iOwnerID)
    m_iTargetX       = iX;
    m_iTargetY       = iY;
    m_iTargetUnitID  = iUnitID;
    m_iTargetOwnerID = iOwnerID;
    CSF_Open();
end

LuaEvents.CSF_OpenPanel.Add(function(iX, iY, iUnitID, iOwnerID)
    print("[CSF] CSF_OpenPanel received: pos=(" .. tostring(iX) .. "," .. tostring(iY) ..
          ") unitID=" .. tostring(iUnitID) .. " owner=" .. tostring(iOwnerID));
    CSF_OpenAt(iX, iY, iUnitID, iOwnerID);
end);

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------
function CSF_Initialize()
    m_EntryIM = InstanceManager:new("CSFCityStateSlot", "CSFEntryButton", Controls.CSFCityStateStack);

    Controls.CSFCloseButton:RegisterCallback(Mouse.eLClick, function() CSF_Close() end);
    Controls.CSFCancelButton:RegisterCallback(Mouse.eLClick, function() CSF_Close() end);
    Controls.CSFConfirmButton:RegisterCallback(Mouse.eLClick, function() CSF_OnConfirm() end);

    Controls.CSFRoot:SetHide(true);

    -- ⭐ 结果轮询兜底：某些 UI 上下文里 GameEvents 为 nil（实测），
    --    这时靠这里定时向 GameCore 拉"最后一次执行结果"。
    --    （用序号判断是不是新结果，避免重复处理。）
    CSF_Safe(function()
        ContextPtr:SetUpdate(function()
            if not m_bWaiting then return end
            local fGet = (ExposedMembers ~= nil and ExposedMembers.CSF ~= nil)
                         and ExposedMembers.CSF.GetLastResult or nil;
            if fGet == nil then return end
            local ok, iSeq, bOk, sReason, iCs = pcall(fGet);
            if not ok or iSeq == nil then return end
            if m_iSeenSeq == nil or iSeq > m_iSeenSeq then
                m_iSeenSeq = iSeq;
                print("[CSF] 轮询到新结果: seq=" .. tostring(iSeq) ..
                      " ok=" .. tostring(bOk) .. " reason=" .. tostring(sReason));
                CSF_OnFoundResult(bOk, sReason, iCs);
            end
        end);
    end);

    -- ESC 关闭  +  Ctrl+E 打开
    --
    -- ⭐⭐ 2026-10-05 新增热键（Ctrl+E）。
    --
    --   为什么加：本 mod 原来**唯一**的面板入口是「建邦使节」单位上的动作，
    --   而那个动作**必须替换 UnitPanel 上下文**才能注入（官方钩子
    --   LateCheckActionBeforeAdd 只能改既有动作，不能凭空新增）。
    --
    --   问题：`CCB经典版` **也替换了 UnitPanel**（LoadOrder 19999，我们 500000）
    --   → ReplaceUIScript 是独占的 → **我们覆盖了它，它的 UnitPanel 功能失效**。
    --
    --   而热键走的是**本面板自己的输入处理器**（InGame 上下文），
    --   **完全不碰 UnitPanel** → **与经典版零冲突**。
    --
    --   注意：热键只是**多一个入口**，使节单位与它的动作都保留不变。
    ContextPtr:SetInputHandler(function(kInputStruct)
        if kInputStruct.keyCode == Keys.VK_ESCAPE and not Controls.CSFRoot:IsHidden() then
            CSF_Close();
            return true;
        end
        -- Ctrl+E：打开/关闭面板
        if kInputStruct.keyCode == Keys.VK_E
           and (kInputStruct.controlDown == true or kInputStruct.ctrlDown == true) then
            if Controls.CSFRoot:IsHidden() then
                print("[CSF] 热键 Ctrl+E：打开面板");
                CSF_Open();
            else
                print("[CSF] 热键 Ctrl+E：关闭面板");
                CSF_Close();
            end
            return true;
        end
        return false;
    end, true);

    print("[CSF] CSF_Panel initialized（面板入口：建邦使节动作 / 热键 Ctrl+E）");
end

ContextPtr:SetInitHandler(CSF_Initialize);
ContextPtr:SetShutdown(function()
    print("[CSF] CSF_Panel shutdown");
end);