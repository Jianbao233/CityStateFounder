-- ===========================================================================
-- CityStateFounder / 城邦缔造者 — 游戏内核心逻辑（GameCore / Script 上下文）
-- 区段：InGameActions > AddGameplayScripts
--
-- 职责：
--   ① 校验地块是否可建城邦（Create 对非法地块【静默失败】，必须自己挡）
--   ② 为指定城邦玩家在指定位置建城（Players[id]:GetCities():Create(x,y)）
--   ③ 建城后复查（静默失败时城市数不变）
--   ④ 善后：删掉该城邦的地图外移民（否则它会自己找地方建城）
--   ⑤ 查询城邦池（供 UI 面板使用）
--
-- ⚠️ 架构约束：
--   - 「缔造者优势 +1 使者」不在这里做——它需要 UI.RequestPlayerOperation
--     （见 UI/CSF_Panel.lua）。GameCore 侧拿不到 PlayerOperations。
--   - UI 与 GameCore 是【两个 Lua VM】，LuaEvents/GameEvents 不跨 VM，
--     必须经 ExposedMembers 桥接。
--
-- 依据（本项目实测）：
--   T-62 休眠城邦可长期稳定存活（50 回合实测）
--   T-25/26 Players[id]:GetCities():Create(x,y) 可用，能把 0 城城邦激活
--   T-27 对非法地块【静默失败】（ok=true 但不建城）→ 必须自校验 + 建后复查
--   T-14 城邦开局拿的是移民，第 1 回合才建城
-- ===========================================================================

print("[CSF] CSF_Gameplay.lua loading (GameCore context)");

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
-- 与其他城市/城邦的最小间距。
--   ⚠️ 取值必须贴近【引擎自己的规则】，否则会出现"合法地形也建不了"：
--      引擎的 `GlobalParameters.CITY_MIN_RANGE = 3`。
--      实测教训（T-122）：我曾把它设成 6，导致用户在任何地方都被拒（`too_close`）。
--      这里取 **3**（与引擎一致），把"是否真的能建"交给引擎判断。
local CSF_MIN_CITY_DISTANCE = 3;

-- ───────────────────────────────────────────────────────────────────────────
-- 【有主地块】开关 —— 决定"能不能在自己领土上建邦"
--   ⚠️ 必须定义在这里（在使用它的 CSF_IsValidFoundLocation 之前）！
--      否则 Lua 读到的是全局 nil，开关会失效（审计脚本抓到过这个 bug）。
--
--   false（**默认**，最安全）：只允许【无主地块】。
--        站在自家/他人领土上时明确报错，提示把「建邦使节」移到无主地。
--        **绝不会因地块归属问题崩游戏。**
--
--   true：允许在【自家领土】上建邦——建城前先 `pPlot:SetOwner(-1)` 解除归属，
--        再复查，仍归他人则中止。
--        ⚠️ 这条路径**尚未实机验证**：用户最新一次崩溃（T-97）正是发生在
--           "校验通过、Create 作用在有主地块上"的场景。官方 AustraliaScenario 用过
--           `SetOwner(-1)`，但本模组尚未在实机上确认它能否消除该崩溃。
--        想试就改成 true，并把 Lua.log 留好。
-- ───────────────────────────────────────────────────────────────────────────
local CSF_ALLOW_OWN_TERRITORY = false;

-- ───────────────────────────────────────────────────────────────────────────
-- 【重定向】开关 —— 默认【关闭】（实测发现严重缺陷，T-109）
--   ⚠️ 必须定义在这里（在使用它的函数之前）！否则 Lua 读到全局 nil，
--      开关会静默失效 —— 这个坑已经踩过两次，由 audit_csf.py 第 ⑨ 项兜住。
--
--   实测结论：把已有休眠城邦"改名"成目标文明**不可用**。
--   `SetPlayerLeader` 只改文明/领袖/等级这三项"名字"，而该玩家的
--   **运行期状态是开局时按【原文明】初始化的，且没有任何 Lua API 能改**
--   （DLL 里 `AddTrait`/`GetTraits`/`RemoveTrait`/`AddModifier`/`SetColor` 全部命中 0）。
--   玩家看到三个毛病：① 旗帜颜色还是原城邦的；② 宗主加成不生效；
--   ③ UI 显示的是缓存的旧名字。且实测出现过**引擎级崩溃**。
--
--   true 会启用（**仅供实验**，会造出半成品城邦并可能崩游戏）。
-- ───────────────────────────────────────────────────────────────────────────
local CSF_ALLOW_RETARGET = false;

-- ───────────────────────────────────────────────────────────────────────────
-- 【建副本】开关 —— 默认【开启】
--   目标文明本局【已被占用】时，再建一个"能力相同、名字不同"的城邦（名字加 " II"）。
--   手法来自 CCB MirrorMap；关键差别是我们必须【显式重新初始化】玩家，
--   否则引擎不会按新文明重建颜色/名字（这就是当年 CSF_ALLOW_RETARGET 出半成品的原因）。
--   详见下方 CSF_FoundCityStateCopy 的头注释。
-- ───────────────────────────────────────────────────────────────────────────
-- ⛔⛔⛔ 2026-10-05：**默认关闭**（用户实测：每次执行都崩，读 NULL+0xb0）
--
--   为什么关：副本路径必须【改变玩家的文明】（把源城邦的文明/领袖设到另一个槽）。
--   实测结论（跨多轮）：
--     · 文明【不变】的路径（复用同文明休眠槽）→ **稳定**（第 5-6 轮验证过，能建城不崩）
--     · 文明【改变】的路径（副本 / 重定向）→ **必崩**
--   原因：改了文明的玩家，其文明/领袖/颜色/特性全部与引擎的预注册不一致，
--         引擎后续处理（UI 颜色表、AI、外交）时踩空。
--
--   要重新试验副本（仅在你明确要求时）：把下面这行改成 true。
--   注意：那会再次触发崩溃，且崩溃【无转储、无 WER 事件】，只能读弹窗。
local CSF_ENABLE_COPY = false;

-- 引擎内部的槽位状态枚举（**不是** Lua 的 SS_*）
--   逆向依据：FUN_180617370 只在状态 ∈ {0,1,3} 时才真正初始化玩家；
--   预注册城邦槽的状态是 5，会被静默拒绝。详见 docs/DLL实时激活城邦_逆向进展.md §9
local CSF_SLOT_AI = 1;

-- ───────────────────────────────────────────────────────────────────────────
-- 【动态创建（AddPlayer）】开关 —— 默认【关闭】
--   ⚠️ 同上：必须在所有使用点之前定义，否则静默失效（已踩两次，audit 兜底）。
--
--   ⚠️⚠️⚠️ 实测结论（T-115）：**引擎不支持在运行时凭空造出一个完整的城邦玩家。**
--      三条路线全部试过，全部失败：
--        ① **全新槽 AddPlayer**（槽 54–61）：
--           文明/领袖/等级/名字/`canInf` 都对，但
--           `UI.GetPlayerColors(54)` = **nil** → 旗帜没有颜色；
--           且 BetterCityStates 在 `CityStates_MPT.lua:374`
--           （`GameInfo.DiplomaticStates[diploStateID]`）崩溃 → 城邦面板整张废掉。
--        ② **复用槽**（`UninitializePlayer(休眠城邦槽)` → `AddPlayer` 拿回同一个槽）：
--           颜色问题解决了（`SetColor nil` 警告消失），建邦当场全部正常，
--           **但之后引擎崩溃**（产生 `.dmp`）。
--        ③ **重定向**（改已有玩家的文明）：颜色/名字/特性全是旧文明的（T-109）。
--      → **唯一 100% 可用的路径是【复用本局已有的城邦】**（引擎自己创建的玩家）。
--
--   想让本局有更多城邦可选：请在**开局设置**里提高城邦数量，或用官方城邦选择界面
--   指定想要的城邦 —— 那些都是引擎在开局时正确创建的，本模组可以正常地把它们
--   放到地图上。
-- ───────────────────────────────────────────────────────────────────────────
-- ★★★★★ 2026-10-06【新路径开关】：激活「该文明自己的未激活预注册槽」
--
--   引擎开局把全部 54 个城邦文明预注册成玩家槽（status=5，未激活）。
--   每个文明有自己专属的槽 → 想建哪个城邦就激活哪个槽。
--   这条路【不改文明】→ 不触发"玩家与引擎预注册不一致"的崩溃。
--
--   实测（2026-10-06，DLL 修复后）：四步配方成功、挂机 4 回合无崩溃、
--   与引擎自己激活的槽状态完全同态。
--
--   ⚠️ 依赖已修复的 DLL（player+0x83a 与子系统写回）；旧 DLL 会崩（NULL+0xb0）。
local CSF_ENABLE_SLOT_ACTIVATION = true;

-- 【数量上限】每个玩家最多同时拥有几个「建邦使节」
--   -1 = 不限制（= 自然上限，即"能造多少就造多少"，按用户要求的默认值）
--    1 = 只能拥有 1 个（移植到别的 MOD 时想要的"仅能生产/购买一次"）
--    2 = 最多 2 个，依此类推
--
--   ⚠️ 为什么用 Lua 而不是数据库：Units 表【没有】MaxPlayerInstances 列
--      （已逐列核实全部 70 列；该字段只存在于 Buildings / GreatPeople / Projects），
--      且游戏里没有 CityCanTrain 这类"能否生产"的钩子（本体与工坊均无）。
--      所以做法是：单位一上地图（Events.UnitAddedToMap）就检查数量，
--      超限则立即消掉。效果 = 硬上限。
local CSF_MAX_ENVOYS_PER_PLAYER = -1;

-- ---------------------------------------------------------------------------
-- 工具：安全取值（GameCore 沙箱里很多东西会抛异常）
-- ---------------------------------------------------------------------------
local function CSF_Safe(f, ...)
    local ok, v = pcall(f, ...);
    if ok then return v end;
    return nil;
end

-- ---------------------------------------------------------------------------
-- 工具：安全取【多个】返回值
--   ⚠️ 2026-10-04 新增：`CSF_Safe` 只返回**第一个**值，
--      所以 `local iW, iH = CSF_Safe(function() return Map.GetGridSize() end)`
--      会让 **iH 永远是 nil** → 地图边缘检查被静默跳过。
--      这是实测发现的真 bug（`FindFoundLocation` 报 `no_map`）。
--      `Map.GetGridSize()` 返回宽、高【两个】值，必须用这个版本取。
-- ---------------------------------------------------------------------------
local function CSF_Safe2(f, ...)
    local ok, a, b, c = pcall(f, ...);
    if ok then return a, b, c end;
    return nil, nil, nil;
end

-- ---------------------------------------------------------------------------
-- 统计某玩家当前拥有几个「建邦使节」（含地图外）
-- ---------------------------------------------------------------------------
local function CSF_CountEnvoys(iPlayerID)
    local pPlayer = Players[iPlayerID];
    if pPlayer == nil then return 0 end

    local iCount = 0;
    local pUnits = CSF_Safe(function() return pPlayer:GetUnits() end);
    if pUnits == nil then return 0 end

    pcall(function()
        for _, pUnit in pUnits:Members() do
            local sType = CSF_Safe(function()
                return GameInfo.Units[pUnit:GetType()].UnitType;
            end);
            if sType == "UNIT_CSF_ENVOY" then
                iCount = iCount + 1;
            end
        end
    end);
    return iCount;
end

-- ---------------------------------------------------------------------------
-- ① 地块合法性校验
--    返回 (ok, reason)
-- ---------------------------------------------------------------------------
-- 地点校验。
--   iFounderOwner：发起建邦的玩家（你的文明）。**允许在自己的领土上建邦**——
--   单位通常就站在自家地盘上，若一律拒绝，功能基本没法用（实测踩到）。
--   仍然拒绝：水域、他人领土、离已有城市太近。
local function CSF_IsValidFoundLocation(iX, iY, iFounderOwner)
    local pPlot = CSF_Safe(function() return Map.GetPlot(iX, iY) end);
    if pPlot == nil then
        return false, "no_plot";
    end

    -- 陆地
    local bWater = CSF_Safe(function() return pPlot:IsWater() end);
    if bWater == true then
        return false, "water";
    end

    -- ⚠️ 地图边界（实测 T-116）：`Create` 在【地图边缘】的格子上会**静默失败**
    --    （实测 (0,35)：`Create returned OK` 但 `cities 0 -> 0`）。
    --    这里保守地留出边界余量，避免让玩家白跑一趟。
    --    ⚠️ API 已核实：`Map.GetGridWidth/GetGridHeight` **不存在**（DLL 命中 0），
    --       正确的是 **`Map.GetGridSize()`**（返回宽、高两个值）。
    local iW, iH = CSF_Safe2(function() return Map.GetGridSize() end);  -- ★ 必须用 Safe2，Safe 只返回一个值
    if iW ~= nil and iH ~= nil then
        if iX < 2 or iY < 2 or iX > (iW - 3) or iY > (iH - 3) then
            return false, "map_edge";
        end
    end

    -- 至少要有相邻陆地（城邦城市需要落脚点）
    --   ⚠️ 原来要求 3 格，实测太严（用户日志 `too_little_land at 17,34`）。
    --      引擎对 1 格小岛也能建城，这里只要求【至少 1 格相邻陆地】。
    local iLand = 0;
    for _, kOff in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
        local pN = CSF_Safe(function() return Map.GetPlot(iX + kOff[1], iY + kOff[2]) end);
        if pN ~= nil then
            local bN = CSF_Safe(function() return pN:IsWater() end);
            if bN == false then iLand = iLand + 1 end
        end
    end
    if iLand < 1 then
        return false, "too_little_land";
    end

    -- 领土：无主地永远允许；有主地取决于 CSF_ALLOW_OWN_TERRITORY
    --   ⚠️ 实测（T-97）：`Create` 作用在【有主地块】上会导致游戏崩溃。
    --      所以默认【拒绝一切有主地块】，这是唯一"保证不崩"的策略。
    local iOwner = CSF_Safe(function() return pPlot:GetOwner() end);
    if iOwner ~= nil and iOwner ~= -1 then
        if not CSF_ALLOW_OWN_TERRITORY then
            -- 默认安全模式：区分"自家"和"他人"，给出更准确的提示
            if iFounderOwner ~= nil and iOwner == iFounderOwner then
                return false, "owned_own";
            end
            return false, "owned_by_other";
        end
        -- 开关打开时：只允许【自家】领土（他人领土仍然拒绝）
        if iFounderOwner == nil or iOwner ~= iFounderOwner then
            return false, "owned_by_other";
        end
    end

    -- 与其他城市的最小间距
    -- ⚠️ 原实现是 `0..100 × 0..100` 逐格 pcall 调 GetCityAt = 10201 次，又慢又危险；
    --    改成遍历在场玩家的城市列表（Members() 迭代）。
    local bTooClose = false;
    local tPlayers = {};
    CSF_Safe(function()
        for _, iPlayer in ipairs(PlayerManager.GetAliveMajorIDs()) do tPlayers[#tPlayers + 1] = iPlayer end
    end);
    CSF_Safe(function()
        for _, iPlayer in ipairs(PlayerManager.GetAliveMinorIDs()) do tPlayers[#tPlayers + 1] = iPlayer end
    end);

    for _, iPlayer in ipairs(tPlayers) do
        local pP = Players[iPlayer];
        if pP ~= nil then
            local pCities = CSF_Safe(function() return pP:GetCities() end);
            if pCities ~= nil then
                -- ⚠️ 用 Members() 遍历。
                --    实测教训：`GetCityByIndex(i)` **在 DLL 里根本不存在**（命中 0），
                --    原来那样写等于距离检查是死代码（每次都被 pcall 吞成 nil）。
                --    Civ6 的集合对象统一用 Members() 迭代（同 pUnits:Members()）。
                --    再套一层 pcall：遍历中若集合变动，迭代器会失效。
                pcall(function()
                    for _, pCity in pCities:Members() do
                        local iCX = CSF_Safe(function() return pCity:GetX() end);
                        local iCY = CSF_Safe(function() return pCity:GetY() end);
                        if iCX ~= nil and iCY ~= nil then
                            local iDist = CSF_Safe(function()
                                return Map.GetPlotDistance(iX, iY, iCX, iCY);
                            end);
                            if iDist ~= nil and iDist < CSF_MIN_CITY_DISTANCE then
                                bTooClose = true;
                            end
                        end
                    end
                end);
            end
        end
    end

    if bTooClose then
        return false, "too_close";
    end

    return true, "ok";
end

-- ---------------------------------------------------------------------------
-- ④b ⭐⭐ 全地图找一个可建邦的地块（**逐级放宽**）
--
--   为什么需要（2026-10-04 实测的真实可用性问题）：
--     在地图拥挤的局面里，调用方自己按"地图中央 + 固定距离"搜索会**一格都找不到**，
--     玩家点「建立城邦」就得到"找不到地"。实测日志：
--         选中 CIVILIZATION_ANTANANARIVO / 目标格 (-1,-1) / ❌ 找不到地
--     当时场上有 9 个城邦各自派了移民（虽然 cities 仍是 0），把"看起来空"的格子占掉了。
--
--   策略（从最理想逐级放宽，任何一级成功就返回）：
--     第 1 轮：全地图 + 模组的完整校验（含最小间距）
--     第 2 轮：允许离城市更近（把 CSF_MIN_CITY_DISTANCE 临时降到 2）
--     第 3 轮：连"有主领土"也允许（临时打开 CSF_ALLOW_OWN_TERRITORY）
--     第 4 轮：只要不是水、不是山、不是地图边缘即可（最后兜底）
--
--   ⚠️ 全程 pcall 包住：任何一步失败只是少一个候选，不会中断搜索。
--
-- @param iFounderOwner  建邦者的玩家 ID（用于领土判断；可为 nil）
-- @return iX, iY, sWhy  —— 失败时返回 -1, -1, 最后一次的拒绝原因
-- ---------------------------------------------------------------------------
local function CSF_FindFoundLocation(iFounderOwner)
    local iW, iH = CSF_Safe2(function() return Map.GetGridSize() end);  -- ★ 必须用 Safe2，Safe 只返回一个值
    if iW == nil or iH == nil then return -1, -1, "no_map" end;

    -- ★★★ 2026-10-05 关键修复：**收集所有存活玩家的单位所在格**
    --
    --   实测崩溃（用户复现）：连续两次调用本函数都返回 (43,2)，
    --   于是【两个移民叠在同一格】→ 引擎崩溃（无转储、无 WER 事件）。
    --
    --   根因：`CSF_IsValidFoundLocation` 的距离检查只统计**城市**
    --   （`GetCities():Members()`）—— 而刚放下的移民**还不是城市**，
    --   所以第二次查找完全看不到它，当然又选中同一格。
    --
    --   修法：把【所有存活玩家（含城邦）的每个单位所在格】记进一张表，
    --   查找时直接跳过。用 "x*1000+y" 做键（地图宽 < 1000 足够）。
    --
    --   ⚠️⚠️ 2026-10-06 追加：**不只是跳过单位所在格，还要避开它周围一圈**。
    --   实测（用户/模拟点击）：
    --     · 移民放在**贴地图边缘**（(5,3)、(27,2)、(34,4)）→ InitUnit 成功，但**建不了城**
    --     · 移民放在**地图正中心 (36,26)**（人类玩家所在地）→ **InitUnit 直接挂起游戏**
    --   所以：既要离边缘够远（能建城），又要离所有单位够远（不挂起）。
    --   这里把"单位所在格及其 8 邻格"都标为禁区（半径 1），再叠加上面的边缘留白。
    local tUnitPlots = {};
    local function collectUnits(tIDs)
        CSF_Safe(function()
            for _, iPlayer in ipairs(tIDs) do
                local pP = Players[iPlayer];
                if pP ~= nil then
                    local pUnits = CSF_Safe(function() return pP:GetUnits() end);
                    if pUnits ~= nil then
                        pcall(function()
                            for _, pUnit in pUnits:Members() do
                                local ux = CSF_Safe(function() return pUnit:GetX() end);
                                local uy = CSF_Safe(function() return pUnit:GetY() end);
                                if ux ~= nil and uy ~= nil and ux >= 0 and uy >= 0 then
                                    -- ★ 单位所在格 + 周围两圈（切比雪夫半径 2）
                                    --   半径 1 实测不够：人类玩家开局有多个单位 + 城市，
                                    --   移民落在它们中间仍会让 InitUnit 挂起。
                                    for ddy = -2, 2 do
                                        for ddx = -2, 2 do
                                            tUnitPlots[(ux + ddx) * 1000 + (uy + ddy)] = true;
                                        end
                                    end
                                end
                            end
                        end);
                    end
                end
            end
        end);
    end
    collectUnits(PlayerManager.GetAliveMajorIDs());
    collectUnits(PlayerManager.GetAliveMinorIDs());
    local nUnitPlots = 0;
    for _ in pairs(tUnitPlots) do nUnitPlots = nUnitPlots + 1 end;
    print("[CSF] 找地：已避开 " .. nUnitPlots .. " 个【有单位的】格子");

    -- 记住原值，搜完恢复（这两个是 local 常量表外的可变开关）
    local iOldDist  = CSF_MIN_CITY_DISTANCE;
    local bOldOwned = CSF_ALLOW_OWN_TERRITORY;

    local sLastWhy = "none";
    local tRounds = {
        { dist = iOldDist, owned = bOldOwned, strict = true  },   -- 第 1 轮：完整校验
        { dist = 2,        owned = bOldOwned, strict = true  },   -- 第 2 轮：放宽间距
        { dist = 1,        owned = true,      strict = true  },   -- 第 3 轮：允许有主领土
        { dist = 1,        owned = true,      strict = false },   -- 第 4 轮：只查地形
    };

    for iRound, kR in ipairs(tRounds) do
        CSF_MIN_CITY_DISTANCE   = kR.dist;
        CSF_ALLOW_OWN_TERRITORY = kR.owned;
        local iFoundX, iFoundY = -1, -1;
        pcall(function()
            -- ★ 遍历整张地图，但**从地图中心向外**扫，并要求**离边缘至少 4 格**。
            --
            --   ⚠️⚠️ 2026-10-06 关键修正（用户实测：激活的城邦 19 回合不建城）：
            --   原来从 (2,2) 开始扫 → 第一个合法格永远是**贴地图边缘**的（实测拿到
            --   (2,2)、(5,3)、(8,2)、(27,2)）→ 移民站在那里**建不了城**：
            --   引擎建城需要周围有足够空间，贴边格不行。
            --   实测对照：引擎自己激活的槽 6/7/8 也卡在边缘、也不建城；而槽 9~14
            --   位置在内部、全部建城成功 → 说明**位置是决定因素**。
            --
            --   修法：① 边缘留 4 格；② 从中心向外螺旋，优先选内部格。
            local iCx = math.floor(iW / 2);
            local iCy = math.floor(iH / 2);
            local iMargin = 4;
            local iMaxR = math.max(iCx, iCy) + 2;
            local bDone = false;
            for iR = 0, iMaxR do
                if bDone then break end
                for dy = -iR, iR do
                    if bDone then break end
                    for dx = -iR, iR do
                        -- 只扫这一圈的边界（切比雪夫环）
                        if iR == 0 or math.abs(dx) == iR or math.abs(dy) == iR then
                            local x = iCx + dx;
                            local y = iCy + dy;
                            if x >= iMargin and x <= iW - 1 - iMargin
                               and y >= iMargin and y <= iH - 1 - iMargin then
                                local pPlot = Map.GetPlot(x, y);
                                if pPlot ~= nil and tUnitPlots[x * 1000 + y] ~= true then
                                    local bWater = false;
                                    local bMtn   = false;
                                    pcall(function() bWater = pPlot:IsWater() end);
                                    pcall(function() bMtn   = pPlot:IsMountain() end);
                                    if bWater == false and bMtn == false then
                                        if kR.strict then
                                            local bOk, sWhy = CSF_IsValidFoundLocation(x, y, iFounderOwner);
                                            if bOk == true then iFoundX, iFoundY = x, y; bDone = true; break end;
                                            sLastWhy = tostring(sWhy);
                                        else
                                            local iLand = 0;
                                            for _, kOff in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                                                local pN = Map.GetPlot(x + kOff[1], y + kOff[2]);
                                                if pN ~= nil then
                                                    local bN = true;
                                                    pcall(function() bN = pN:IsWater() end);
                                                    if bN == false then iLand = iLand + 1 end;
                                                end
                                            end
                                            if iLand >= 1 then iFoundX, iFoundY = x, y; bDone = true; break end;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end);
        if iFoundX > 0 then
            -- 恢复开关
            CSF_MIN_CITY_DISTANCE   = iOldDist;
            CSF_ALLOW_OWN_TERRITORY = bOldOwned;
            print("[CSF] 找地成功：(" .. iFoundX .. "," .. iFoundY .. ") 第 "
                  .. iRound .. " 轮（间距=" .. kR.dist
                  .. " 允许有主=" .. tostring(kR.owned)
                  .. " 严格校验=" .. tostring(kR.strict) .. "）");
            return iFoundX, iFoundY, "ok";
        end
    end

    -- 恢复开关
    CSF_MIN_CITY_DISTANCE   = iOldDist;
    CSF_ALLOW_OWN_TERRITORY = bOldOwned;
    print("[CSF] ❌ 全地图四轮搜索都没找到可建邦的地（最后原因：" .. sLastWhy .. "）");
    return -1, -1, sLastWhy;
end

-- ---------------------------------------------------------------------------
-- ④ 删掉某玩家的【地图外】单位
--    地图外单位的坐标是 (-9999,-9999)（引擎哨兵值，实测确认）
--
--    ⚠️⚠️ 必须【先收集、后删除】！
--        原实现直接在 `for _, pUnit in pUnits:Members() do ... UnitManager.Kill(pUnit) end`
--        的循环体里杀单位 —— **边遍历边改集合会让迭代器失效**，行为未定义，
--        是潜在的引擎崩溃点（本文件别处早已写明这条规则，这里却违反了）。
--        改为：第一遍只收集候选，第二遍统一 kill。
-- ---------------------------------------------------------------------------
local function CSF_DeleteOffmapUnits(iPlayerID)
    local pPlayer = Players[iPlayerID];
    if pPlayer == nil then return 0 end

    local pUnits = CSF_Safe(function() return pPlayer:GetUnits() end);
    if pUnits == nil then return 0 end

    -- 第一遍：只收集，不改动任何东西
    local tOffmap = {};
    pcall(function()
        for _, pUnit in pUnits:Members() do
            local iX = CSF_Safe(function() return pUnit:GetX() end);
            local iY = CSF_Safe(function() return pUnit:GetY() end);
            if iX ~= nil and iY ~= nil and (iX < 0 or iY < 0) then
                tOffmap[#tOffmap + 1] = pUnit;
            end
        end
    end);

    -- 第二遍：统一删除（此时已不在 Members() 遍历中）
    local iKilled = 0;
    for _, pUnit in ipairs(tOffmap) do
        local bOk = pcall(function() UnitManager.Kill(pUnit, false) end);
        if bOk then iKilled = iKilled + 1 end
    end

    print("[CSF] deleted " .. tostring(iKilled) .. " offmap unit(s) of player " ..
          tostring(iPlayerID) .. " (candidates " .. tostring(#tOffmap) .. ")");
    return iKilled;
end

-- ---------------------------------------------------------------------------
-- ④b 消耗掉用来建邦的「建邦使节」单位
--
--    ⚠️⚠️ 为什么必须【在 Create 之前】调用（实测 T-112）：
--        用户实机崩溃的日志精确停在 `[step] cities:Create(48,13) ...`（没有 returned OK）。
--        对照我自己的测试：全部传的是 `unitID = nil`（那一格上没有单位）→ 从未崩过。
--        真实使用时，**建邦使节就站在那一格上**，于是出现了
--        「玩家 0 的单位」与「玩家 54 的城市」同占一格 → 引擎状态冲突 → 崩溃。
--        做法：**先把使节消耗掉（腾空这一格），再建城**。使节本来就是要被消耗的，
--        只是原来的顺序反了。
--
--    优先级 1：用 UI 传来的【单位 ID + 拥有者 ID】精确定位（最可靠）
--    优先级 2：退化为按坐标扫描所有主文明的单位
--    ⚠️ 必须先收集、后删除：遍历 pUnits:Members() 时 Kill 会让迭代器失效。
-- ---------------------------------------------------------------------------
local function CSF_ConsumeEnvoy(iX, iY, iUnitID, iOwnerID)
    if iX == nil or iY == nil then return 0 end

    local tToKill = {};
    local tSeen   = {};

    local function AddCandidate(pUnit)
        if pUnit == nil then return end
        local iID = CSF_Safe(function() return pUnit:GetID() end);
        if iID ~= nil and tSeen[iID] then return end
        if iID ~= nil then tSeen[iID] = true end
        tToKill[#tToKill + 1] = pUnit;
    end

    -- 优先级 1：按单位 ID 直接取
    if iUnitID ~= nil and iOwnerID ~= nil then
        local pDirect = CSF_Safe(function() return UnitManager.GetUnit(iOwnerID, iUnitID) end);
        if pDirect ~= nil then
            print("[CSF] consume: found envoy by ID (owner=" .. tostring(iOwnerID) ..
                  " unit=" .. tostring(iUnitID) .. ")");
            AddCandidate(pDirect);
        else
            print("[CSF] consume: GetUnit(" .. tostring(iOwnerID) .. "," ..
                  tostring(iUnitID) .. ") = nil; 退回坐标扫描");
        end
    end

    -- 优先级 2：按坐标扫（仅当上面没拿到时才做，避免误删别的单位）
    if #tToKill == 0 then
        local tMajors = CSF_Safe(function() return PlayerManager.GetAliveMajorIDs() end) or {};
        for _, iMajor in ipairs(tMajors) do
            local pM = Players[iMajor];
            if pM ~= nil then
                local pUnits = CSF_Safe(function() return pM:GetUnits() end);
                if pUnits ~= nil then
                    pcall(function()
                        for _, pUnit in pUnits:Members() do
                            local uX = CSF_Safe(function() return pUnit:GetX() end);
                            local uY = CSF_Safe(function() return pUnit:GetY() end);
                            local sType = CSF_Safe(function()
                                return GameInfo.Units[pUnit:GetType()].UnitType;
                            end);
                            if sType == "UNIT_CSF_ENVOY" and uX == iX and uY == iY then
                                AddCandidate(pUnit);
                            end
                        end
                    end);
                end
            end
        end
    end

    local iKilled = 0;
    for _, pUnit in ipairs(tToKill) do
        local bOk = pcall(function() UnitManager.Kill(pUnit, false) end);
        if bOk then iKilled = iKilled + 1 end
    end
    print("[CSF] consume done, killed=" .. tostring(iKilled));
    return iKilled;
end

-- ---------------------------------------------------------------------------
-- ② + ③ 建城邦主流程
--    返回 (ok, reason)
-- ---------------------------------------------------------------------------
local function CSF_FoundCityState(iCityStateID, iX, iY, iUnitID, iOwnerID)
    if iCityStateID == nil or iX == nil or iY == nil then
        return false, "bad_args";
    end

    local pPlayer = Players[iCityStateID];
    if pPlayer == nil then
        return false, "no_player";
    end

    local bAlive = CSF_Safe(function() return pPlayer:IsAlive() end);
    if bAlive ~= true then
        return false, "dead";
    end

    -- ① 自校验地块
    --    ⚠️ 必须把 iOwnerID（发起建邦的玩家）传进去，与调用方的【预验证】保持完全一致。
    --       否则会出现：预验证通过（自家领土 OK）→ 创建了玩家 → 这里又不通过
    --       → 留下孤儿玩家（实测踩到的崩溃路径）。
    local bValid, sReason = CSF_IsValidFoundLocation(iX, iY, iOwnerID);
    if not bValid then
        print("[CSF] invalid location (" .. tostring(sReason) .. ") at " .. tostring(iX) .. "," .. tostring(iY));
        return false, sReason;
    end

    -- 记录建城前的城市数（用于复查）
    local iBefore = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;

    -- ①b ⚠️⚠️ 关键安全步骤：把地块归属清空后再建城
    --     实测证据（T-97）：第 24 次崩溃时校验【已通过】（放宽后允许自家领土），
    --     于是 `Create` 第一次真正作用在【有主地块】上 → 游戏崩溃。
    --     对照：我所有成功测试都在【无主地块】上。
    --     机理推测：在属于 A 的地块上给 B 建城，会造成领土归属冲突 → 引擎数据不一致。
    --     做法：先 SetOwner(-1) 解除归属；**再复查**，若仍归属他人则【中止】，
    --           绝不冒险调用 Create（宁可报错也不能崩游戏）。
    local pPlot = CSF_Safe(function() return Map.GetPlot(iX, iY) end);
    if pPlot ~= nil then
        local iPlotOwner = CSF_Safe(function() return pPlot:GetOwner() end);
        if iPlotOwner ~= nil and iPlotOwner ~= -1 then
            print("[CSF] [step] plot (" .. tostring(iX) .. "," .. tostring(iY) ..
                  ") owned by " .. tostring(iPlotOwner) .. " -> clearing owner before Create");
            pcall(function() pPlot:SetOwner(-1) end);
            local iAfterClear = CSF_Safe(function() return pPlot:GetOwner() end);
            if iAfterClear ~= nil and iAfterClear ~= -1 then
                print("[CSF] [step] ABORT: 地块归属未能清空（仍属 " ..
                      tostring(iAfterClear) .. "），不调用 Create");
                return false, "owned_not_cleared";
            end
            print("[CSF] [step] plot owner cleared -> now unowned");
        end
    end

    -- ①c ⚠️⚠️ 关键顺序：**先把建邦使节消耗掉，腾空这一格，再建城**（T-112）
    --     实测崩溃日志精确停在这里：`[step] cities:Create(48,13) ...`（无 returned OK）。
    --     原因：使节（玩家 0 的单位）还站在那一格上，而我们要给玩家 54 在同一格建城
    --     → 一格同时有两个玩家的对象 → 引擎崩溃。
    print("[CSF] [step] consume envoy BEFORE Create (unitID=" .. tostring(iUnitID) ..
          " owner=" .. tostring(iOwnerID) .. ")");
    CSF_ConsumeEnvoy(iX, iY, iUnitID, iOwnerID);
    print("[CSF] [step] consume before Create done");

    -- ② 建城（核心 API）
    --    细粒度日志：万一崩在这儿，日志能精确到这一步（T-94 排查手段）
    print("[CSF] [step] cities:Create(" .. tostring(iX) .. "," .. tostring(iY) ..
          ") player=" .. tostring(iCityStateID) .. " before=" .. tostring(iBefore));
    local bCalled = pcall(function()
        pPlayer:GetCities():Create(iX, iY);
    end);
    if not bCalled then
        return false, "create_threw";
    end
    print("[CSF] [step] cities:Create returned OK");

    -- ③ 复查：Create 对非法地块【静默失败】——不报错但城市数不变
    local iAfter = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;
    if iAfter <= iBefore then
        print("[CSF] Create silently failed (cities " .. tostring(iBefore) .. " -> " .. tostring(iAfter) .. ")");
        -- ⚠️ 补偿：使节已经在上一步被消耗了，但城没建成。
        --    在这里【在同格重生一个使节】，避免玩家白白损失一个单位（T-116）。
        if iOwnerID ~= nil then
            local bBack = pcall(function()
                UnitManager.InitUnit(iOwnerID, "UNIT_CSF_ENVOY", iX, iY);
            end);
            print("[CSF] 建城失败 → 已在 (" .. tostring(iX) .. "," .. tostring(iY) ..
                  ") 补偿重生使节，ok=" .. tostring(bBack));
        end
        return false, "silent_fail";
    end

    -- ④ 善后 a：删掉该城邦的地图外移民
    print("[CSF] [step] DeleteOffmapUnits(" .. tostring(iCityStateID) .. ")");
    CSF_DeleteOffmapUnits(iCityStateID);
    print("[CSF] [step] DeleteOffmapUnits done");

    -- ④ 善后 b：消耗使节 —— **已提前到 Create 之前执行**（见上方 ①c，T-112）。
    --    这里不再重复消耗，避免二次删除。

    print("[CSF] city-state " .. tostring(iCityStateID) .. " founded at " ..
          tostring(iX) .. "," .. tostring(iY) .. " (cities " ..
          tostring(iBefore) .. " -> " .. tostring(iAfter) .. ")");

    return true, "ok";
end

-- ---------------------------------------------------------------------------
-- ⑤ 城邦池查询（供 UI 面板用；GameCore 侧也能跑 DB.ConfigurationQuery）
-- ---------------------------------------------------------------------------
local function CSF_GetCityStatePool()
    local sDomain = "Expansion2CityStates";
    local sRuleset = CSF_Safe(function() return GameConfiguration.GetValue("RULESET") end);
    if sRuleset == "RULESET_EXPANSION_1" then
        sDomain = "Expansion1CityStates";
    elseif sRuleset ~= "RULESET_EXPANSION_2" then
        sDomain = "StandardCityStates";
    end

    local tRows = CSF_Safe(function()
        return DB.ConfigurationQuery(
            "SELECT CivilizationType, Name, Icon, CityStateCategory, Bonus, Bonus_XP1, Bonus_XP2 " ..
            "FROM CityStates WHERE Domain = ? ORDER BY CityStateCategory, CivilizationType", sDomain);
    end);

    local tOut = {};
    if tRows ~= nil then
        for _, row in ipairs(tRows) do
            tOut[#tOut + 1] = {
                CivType  = row.CivilizationType,
                Name     = row.Name,
                Icon     = row.Icon,
                Category = row.CityStateCategory,
                Bonus    = row.Bonus,
                BonusXP1 = row.Bonus_XP1,
                BonusXP2 = row.Bonus_XP2,
            };
        end
    end
    print("[CSF] pool domain=" .. tostring(sDomain) .. " count=" .. tostring(#tOut));
    return tOut;
end

-- ---------------------------------------------------------------------------
-- ⑥ 本局【休眠中】的城邦（= 预留槽位，玩家真正能选的目标）
--
--    ⚠️ 设计要点（T-65）：预留城邦的身份在【地图生成时】就固定了，
--    运行时【改不了】（PlayerConfigurations:SetLeaderTypeName 在 GameCore 为 nil）。
--    所以面板只能列出"本局已休眠的城邦"，而不是全池。
--    这与用户已确认的 D-09「城邦池开局前定」一致。
--
--    每个条目 = 休眠城邦玩家 + 它在 CityStates 配置表里的展示数据
--    （名称 / 图标 / 类别 / 三档加成 LOC 键）
-- ---------------------------------------------------------------------------
local function CSF_GetDormantCityStates()
    -- 先把 CityStates 配置表读成 map：CivilizationType -> row
    local tPool = {};
    local sRuleset = CSF_Safe(function() return GameConfiguration.GetValue("RULESET") end);
    local sDomain = "Expansion2CityStates";
    if sRuleset == "RULESET_EXPANSION_1" then
        sDomain = "Expansion1CityStates";
    elseif sRuleset ~= "RULESET_EXPANSION_2" then
        sDomain = "StandardCityStates";
    end

    local tRows = CSF_Safe(function()
        return DB.ConfigurationQuery(
            "SELECT CivilizationType, Name, Icon, CityStateCategory, Bonus, Bonus_XP1, Bonus_XP2 " ..
            "FROM CityStates WHERE Domain = ?", sDomain);
    end);
    if tRows ~= nil then
        for _, row in ipairs(tRows) do
            tPool[row.CivilizationType] = row;
        end
    end

    -- 再枚举存活城邦玩家，挑出【休眠】的（0 城）
    local tOut = {};
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    for _, iPlayer in ipairs(tIDs) do
        local pPlayer = Players[iPlayer];
        if pPlayer ~= nil then
            local iCities = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;
            if iCities == 0 then
                local sCiv    = CSF_Safe(function() return PlayerConfigurations[iPlayer]:GetCivilizationTypeName() end);
                local sLeader = CSF_Safe(function() return PlayerConfigurations[iPlayer]:GetLeaderTypeName() end);
                local row     = (sCiv ~= nil) and tPool[sCiv] or nil;

                tOut[#tOut + 1] = {
                    PlayerID = iPlayer,
                    Civ      = sCiv,
                    Leader   = sLeader,
                    -- 池里查不到就退化显示（例如 mod 加的城邦不在配置表）
                    Name     = (row ~= nil) and row.Name     or ("LOC_CIVILIZATION_" .. tostring(sCiv) .. "_FRONTEND_NAME"),
                    Icon     = (row ~= nil) and row.Icon     or ("ICON_" .. tostring(sCiv)),
                    Category = (row ~= nil) and row.CityStateCategory or "UNKNOWN",
                    Bonus    = (row ~= nil) and row.Bonus    or nil,
                    BonusXP1 = (row ~= nil) and row.Bonus_XP1 or nil,
                    BonusXP2 = (row ~= nil) and row.Bonus_XP2 or nil,
                };
            end
        end
    end

    print("[CSF] dormant city-states = " .. tostring(#tOut) ..
          " (domain=" .. tostring(sDomain) .. ", pool=" .. tostring(#tRows or 0) .. ")");
    return tOut;
end

-- ---------------------------------------------------------------------------
-- ⑦ 运行时预留：开局把 N 个城邦「送下地图」保持休眠
--
--    为什么不用地图脚本（AssignStartingPlots.lua）：
--      那条路线要覆盖原生同名文件，会与 CCB Maps（include("AssignStartingPlots")）
--      和 Free City States（Override/XP2/AssignStartingPlots.lua）三方抢同一份文件
--      —— 实测已在单机开局时引发
--        BBM_AssignStartingPlots.lua:353 attempt to index a nil value / GenerateMap 失败。
--      所以改走运行时，完全不碰地图脚本。
--
--    机制（S0 已实测：这样造出的休眠城邦可稳定存活 50 回合且保持 0 城）：
--      ① UnitManager.InitUnit(id, "UNIT_SETTLER", -1, -1)  → 地图外给一个移民（保命）
--      ② 杀掉它在地图上的全部单位                        → 它没有起始位置，不会自己建城
--
--    事件选择依据 FreeCityStates.lua 的既有钩子：
--      Events.LoadScreenClose  —— 读档/开局完成，赶在第 1 回合处理之前
--      Events.UnitAddedToMap   —— 单位上地图时拦截（防止预留城邦的单位溜回地图）
-- ---------------------------------------------------------------------------
-- 【地图上保留几座城邦】—— 决定世界看起来有多"正常"
--   语义：开局时本局有 T 个城邦玩家（T 由【开局设置】决定）。
--         其中若干座正常留在地图上、照常建城；其余的（T − 保留数）
--         全部送下地图保持休眠，供玩家用建邦使节放置。
--
--   取值：
--     >= 0 = 【绝对值】留 N 座在地图上（其余 T − N 可建）
--       -1 = 全部留在地图上（= 纯原版行为，面板里没有可建的城邦）
--       -2 = 【按比例】（**默认**）—— 用下面的 CSF_KEEP_ACTIVE_PERCENT
--
--   ⭐ 为什么默认用比例而不是固定值（T-146）：
--      固定值在小地图上会让功能**静默失效**。例如固定 6：
--        · 决斗图默认只有 3 个城邦 → 3 − 6 夹到 0 → **一个都建不了**
--        · 决斗图拉满 6 个         → 6 − 6 = 0   → **一个都建不了**
--      玩家造出建邦使节却发现"没东西可建"，且没有任何提示。
--      比例制在任意地图尺寸下都保证"有得建"。
--
--   上限（官方 MapSizes.xml 的 MaxCityStates）：
--     Duel 6 / Tiny 10 / Small 14 / Standard 18 / Large 22 / Huge 24
--   官方默认值（DefaultCityStates）：
--     Duel 3 / Tiny 6 / Small 9 / Standard 12 / Large 15 / Huge 18
--
--   ⭐ 想要"地图观感与原版一致 + 多出来的全部可建"：
--     在开局【高级设置】里用官方【城邦选择器】勾一个大候选池、把城邦数量拉满，
--     再把 CSF_KEEP_ACTIVE_ON_MAP 设成官方 DefaultCityStates 的数值。
--     （详见 Data/CSF_MapSizes.sql 的说明）
local CSF_KEEP_ACTIVE_ON_MAP = -2;

-- 按比例保留时，留在地图上的百分比（1..100）
--   50 = 一半留在地图上、一半可建（**默认**）
--        标准图 12 个 → 6 留 + 6 可建（与旧的固定值 6 行为一致）
--        决斗图  3 个 → 2 留 + 1 可建（旧固定值下这里是 0 可建）
--   0  = 全部可建（地图上没有城邦，⚠️ 世界会很空）
--   100= 全部留在地图上（= 纯原版，没有可建的）
-- ⭐⭐ 保留比例：越低，「可建」的城邦越多。
        --    18 个城邦时的对照：
        --      50%  -> 地图 9 座 + 可建 9 座
        --      35%  -> 地图 6 座 + 可建 12 座   ← 当前
        --      20%  -> 地图 4 座 + 可建 14 座
        --      0%   -> 地图 0 座 + 可建 18 座
        --    ⚠️ 本模组额外造的城邦（补丁兜底的、带 CSF_EXTRA_DORMANT 标记的）
        --       永远不藏 —— 对它们动手会让引擎原生崩溃。
        local CSF_KEEP_ACTIVE_PERCENT = 67;

-- ---------------------------------------------------------------------------
-- 【额外休眠城邦】—— 开局"凭空"多造几个城邦玩家，让玩家有更多可选（T-144）
-- ---------------------------------------------------------------------------
--   ⛔⛔⛔ 【本方案已实测否决 —— 不要打开】⛔⛔⛔
--
--   目标（用户要求）：
--     · 开局设置界面【完全不变】
--     · 地图上【和原版一样】，正常生成开局前决定好的数量
--     · 但面板里可选的城邦【更多】
--
--   做法（已实现并实测）：LoadScreenClose 时用 AddPlayer 造 N 个【本局没有的】
--     城邦玩家，造完立刻送下地图休眠。它们从不上地图，所以地图看起来和原版一样。
--
--   ✅ 实测成功的部分（2026-09-26 独立复现）：
--     · 创建稳定（两次独立开局都拿到槽 54–57，文明/领袖正确）
--     · 真的是休眠（cities=0 onMap=0 alive=true）、真的没上地图
--     · 面板可建数 3 → 7（原生休眠 3 + 额外 4）
--     · 不会因"缺起始位置"被引擎移除（连续存活 4 分钟以上）
--     · A/B 对照：关闭/开启各跑 4 分钟心跳，两组都全程存活
--
--   ❌ 但这两条致命问题让本方案【不可用】（与 T-115 结论完全一致）：
--     ① 【没有颜色】`UI.GetPlayerColors(54..57)` 全部返回 nil，而原生城邦
--        （含资料片的）都返回 -15198184。**颜色是按【玩家槽】解析的**，
--        AddPlayer 走的不是引擎初始化玩家的路径。
--        反证：CIVILIZATION_ANTIOCH 在 Expansion1_PlayerColors.xml 里【有】
--        颜色定义，我们的槽 55 依然 nil → 证明按槽不按文明。
--        **DLL 里只有 `GetColor`、没有 `SetColor`** → 运行时无法补。
--     ② 【破坏城邦面板 / 引擎不稳定】T-115 实测：BetterCityStates 在
--        `CityStates_MPT.lua:374` 崩溃（`GameInfo.DiplomaticStates[diploStateID]`
--        为 nil）→ **城邦面板整张显示 `$占位符$` 且不可用**。
--        本次复测也观察到：建一个额外城邦时游戏**挂起**
--        （Responding=False、FireTuner 端口关闭、CPU 近零增长）。
--
--   → **结论：引擎不支持在运行时凭空造出机制完整的城邦玩家。**
--     要"更多可选城邦"，唯一可行的杠杆是【提高本局城邦总数】
--     （见 Data/CSF_MapSizes.sql），代价是开局设置界面的滑条会变。
--
--   保留本实现的价值：它是一份【已排除方案的可执行记录】。将来若有人想重走
--   这条路，看这里的结论即可，不必再踩一遍。
--
--   取值：**永久为 0**
--
--   ⛔⛔⛔ 2026-10-04 用户底线（必须遵守）：
--      "不能影响开局的时候城邦的数量，就按照玩家想要多少用多少，我们不干涉这块。"
--      → 本开关【永久保持 0】，城邦数量完全由玩家在开局设置里决定。
--
--   要在对局中新增城邦，走 DLL 路线（见 docs/DLL版_调研设计与计划.md）：
--      (a) 激活【预注册但 alive=false】的槽（地图生成时没出现过、但该局允许存在）
--      (b) 复制一个【已存在】的城邦（能力/颜色全复用，只有名字 + 内部 ID 不同）
--   Lua 层两条路都实测会原生崩溃，必须下沉到 DLL 直接操作引擎内部数据。
local CSF_EXTRA_DORMANT_COUNT = 0;

-- 额外城邦是否补起始位置（实验用，同样已否决）
--   ⚠️ 实测把这项打开后，游戏在开局后【立刻死亡】，比不补更糟 ——
--      SetRandomMinorStartingPosition 用在 AddPlayer 新建的槽上很可能与
--      已分配的位置冲突。**保持 false。**
local CSF_EXTRA_SET_START_POS = false;

local m_tReserved = {};          -- 已预留的城邦 playerID 集合
local m_tOrphan   = {};          -- 【动态创建后建城失败】留下的玩家：Civ -> playerID
                                 -- 下次建同一文明时复用它，避免反复 AddPlayer 累积孤儿
                                 -- （孤儿玩家会卡在引擎里，累积后导致崩溃——实测踩到）

local function CSF_IsReserved(iPlayerID)
    return m_tReserved[iPlayerID] == true;
end

-- 把某城邦的地图外移民补上，并清掉它在地图上的一切单位
local function CSF_SendPlayerOffMap(iPlayerID)
    local pPlayer = Players[iPlayerID];
    if pPlayer == nil then return false end

    local bAlive = CSF_Safe(function() return pPlayer:IsAlive() end);
    if bAlive ~= true then return false end

    -- ① 地图外给一个移民（引擎会把坐标落到 (-9999,-9999)）
    CSF_Safe(function()
        UnitManager.InitUnit(iPlayerID, "UNIT_SETTLER", -1, -1);
    end);

    -- ② 杀掉地图上的单位
    --    ⚠️ 必须【先收集、后删除】：原实现在 `for _, pUnit in pUnits:Members() do`
    --       的循环体里直接 `UnitManager.Kill(pUnit)` —— **边遍历边改集合会让迭代器失效**，
    --       行为未定义，是潜在的引擎崩溃点。而且这段**每次读档都会执行**
    --       （日志实测：每个预留城邦杀 3 个单位 × 8 个城邦）。
    local tOnMap = {};
    local pUnits = CSF_Safe(function() return pPlayer:GetUnits() end);
    if pUnits ~= nil then
        pcall(function()
            for _, pUnit in pUnits:Members() do
                local x = CSF_Safe(function() return pUnit:GetX() end);
                local y = CSF_Safe(function() return pUnit:GetY() end);
                if x ~= nil and y ~= nil and (x >= 0 or y >= 0) then
                    tOnMap[#tOnMap + 1] = pUnit;
                end
            end
        end);
    end

    local iKilled = 0;
    for _, pUnit in ipairs(tOnMap) do
        local bOk = pcall(function() UnitManager.Kill(pUnit, false) end);
        if bOk then iKilled = iKilled + 1 end
    end

    print("[CSF] reserve: city-state " .. tostring(iPlayerID) ..
          " sent off-map (killed " .. tostring(iKilled) .. " on-map unit(s), candidates " ..
          tostring(#tOnMap) .. ")");
    return true;
end

local function CSF_GetLeaderForCiv(sCiv)
    if sCiv == nil or sCiv == "" then return nil end

    -- ① 遍历匹配（主要途径）
    local sLeader = nil;
    pcall(function()
        for row in GameInfo.CivilizationLeaders() do
            if row.CivilizationType == sCiv then
                sLeader = row.LeaderType;
            end
        end
    end);
    if sLeader ~= nil and sLeader ~= "" then return sLeader end

    -- ② 命名规律 + 存在性验证（兜底）
    local sGuess = "LEADER_MINOR_CIV_" .. string.gsub(sCiv, "^CIVILIZATION_", "");
    local kLeader = nil;
    pcall(function() kLeader = GameInfo.Leaders[sGuess] end);
    if kLeader ~= nil then return sGuess end

    -- ③ 都不行 → 返回 nil（调用方必须中止，绝不能把 nil 传给引擎）
    return nil;
end

-- ===========================================================================
-- 【额外休眠城邦】开局凭空多造 N 个城邦玩家（T-144，路线 C）
-- ===========================================================================
--   时机：LoadScreenClose —— 地图已生成、第 1 回合尚未开始。
--   目的：地图保持原版外观，但面板里可选的城邦更多。
--   返回：实际创建成功的个数。
--
--   安全性设计（逐条对应已知雷区）：
--     · 只挑【本局没有的】城邦文明 → 不会造出重复文明
--     · 领袖必须先查得到（传 nil 给 SetPlayerLeader = 引擎空指针崩溃，T-89）
--     · 创建后【立刻】送下地图 + 标记预留 → 不会在地图上留下痕迹
--     · 全程 pcall 包裹 → 任何一步失败都只是少造一个，不会崩
--     · 默认关闭（CSF_EXTRA_DORMANT_COUNT = 0）
local function CSF_CreateExtraDormantCityStates()
    if CSF_EXTRA_DORMANT_COUNT == nil or CSF_EXTRA_DORMANT_COUNT <= 0 then
        return 0;
    end

    -- ⛔ 已否决方案的响亮警告（T-144 / T-115）
    print("[CSF] ⛔⛔ extra: CSF_EXTRA_DORMANT_COUNT = " .. tostring(CSF_EXTRA_DORMANT_COUNT) ..
          " —— 这是一个【已实测否决】的方案！");
    print("[CSF] ⛔⛔ extra: 已知后果 = ① 新造的城邦【没有颜色】(UI.GetPlayerColors = nil，");
    print("[CSF] ⛔⛔ extra:   引擎没有 SetColor API 可补) ② BetterCityStates 会在");
    print("[CSF] ⛔⛔ extra:   CityStates_MPT.lua:374 崩溃 → 城邦面板显示 $占位符$ 且不可用");
    print("[CSF] ⛔⛔ extra:   ③ 建邦时游戏可能挂起。详见 CSF_Gameplay.lua 顶部注释与决策记录 T-144。");

    local pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager() or nil;
    if pm == nil then
        print("[CSF] extra: WorldBuilder.PlayerManager 不可用，跳过");
        return 0;
    end

    -- ① 本局【已被占用】的城邦文明 —— 不能重复造
    --    ⚠️⚠️ 必须扫【所有槽位】，不能只看 GetAliveMinorIDs()！
    --    实测踩到：槽 50–53 是 status=5 的【预分配槽】，它们持有城邦文明
    --    （如 CIVILIZATION_ANTANANARIVO）但**不在 GetAliveMinorIDs() 里**。
    --    只查存活列表 → 我们又造了一个同文明的玩家 → **本局出现两个同名文明**。
    local tUsed = {};
    local tExisting = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    for _, iPlayer in ipairs(tExisting) do
        local sCiv = CSF_Safe(function()
            return PlayerConfigurations[iPlayer]:GetCivilizationTypeName();
        end);
        if sCiv ~= nil then tUsed[sCiv] = true end
    end
    -- 再把所有槽位（含 status=5 预分配槽、主文明、城邦）扫一遍
    local iSlotScanned = 0;
    for iSlot = 0, 63 do
        local sCiv = CSF_Safe(function()
            return PlayerConfigurations[iSlot]:GetCivilizationTypeName();
        end);
        if sCiv ~= nil and sCiv ~= "" then
            tUsed[sCiv] = true;
            iSlotScanned = iSlotScanned + 1;
        end
    end
    print("[CSF] extra: 已占用文明 " .. tostring(iSlotScanned) .. " 个（含预分配槽），存活城邦 " ..
          tostring(#tExisting) .. " 个");

    -- ② 候选：城邦池里【本局没有】的那些（按规则集取 Domain）
    local sRuleset = CSF_Safe(function() return GameConfiguration.GetValue("RULESET") end);
    local sDomain = "Expansion2CityStates";
    if sRuleset == "RULESET_EXPANSION_1" then
        sDomain = "Expansion1CityStates";
    elseif sRuleset ~= "RULESET_EXPANSION_2" then
        sDomain = "StandardCityStates";
    end

    local tCand = {};
    local tRows = CSF_Safe(function()
        return DB.ConfigurationQuery(
            "SELECT CivilizationType, Name FROM CityStates WHERE Domain = ?", sDomain);
    end) or {};
    for _, row in ipairs(tRows) do
        local sCiv = row.CivilizationType;
        if sCiv ~= nil and not tUsed[sCiv] then
            tCand[#tCand + 1] = sCiv;
        end
    end
    print("[CSF] extra: 本局已有 " .. tostring(#tExisting) .. " 个城邦，池里可用的新文明 " ..
          tostring(#tCand) .. " 个；目标额外造 " .. tostring(CSF_EXTRA_DORMANT_COUNT) .. " 个");

    -- ③ 逐个创建
    local iMade = 0;
    for i = 1, CSF_EXTRA_DORMANT_COUNT do
        local sCiv = tCand[i];
        if sCiv == nil then
            print("[CSF] extra: 候选已用尽（只造出 " .. tostring(iMade) .. " 个）");
            break
        end

        -- 领袖必须查得到（T-89：传 nil 会崩）
        local sLeader = CSF_GetLeaderForCiv(sCiv);
        if sLeader == nil then
            print("[CSF] extra: " .. tostring(sCiv) .. " 查不到领袖，跳过");
        else
            -- ③a AddPlayer 拿一个槽
            local iNew = nil;
            local bAdd = pcall(function() iNew = pm:AddPlayer(true) end);
            if (not bAdd) or iNew == nil then
                print("[CSF] extra: AddPlayer 失败（空槽用尽？）—— 已造 " .. tostring(iMade) .. " 个，停止");
                break
            end

            -- ③b 定文明/领袖/等级（顺序关键：T-111）
            local bLead = pcall(function()
                pm:SetPlayerLeader(iNew, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE");
            end);
            if not bLead then
                print("[CSF] extra: SetPlayerLeader(" .. tostring(iNew) .. ", " .. tostring(sCiv) ..
                      ") 失败 —— 停止（避免留下半成品玩家）");
                break
            end

            -- ③c 起始位置（默认不补 —— 补了就可能真的上地图）
            if CSF_EXTRA_SET_START_POS then
                local bPos = pcall(function() pm:SetRandomMinorStartingPosition(iNew) end);
                print("[CSF] extra: SetRandomMinorStartingPosition(" .. tostring(iNew) ..
                      ") ok=" .. tostring(bPos));
            end

            -- ③d 立刻送下地图 + 标记预留（这样它永远不会在地图上出现）
            local bOff = CSF_SendPlayerOffMap(iNew);
            if bOff then m_tReserved[iNew] = true end

            iMade = iMade + 1;
            print("[CSF] extra: ✅ 创建城邦玩家 " .. tostring(iNew) .. " = " .. tostring(sCiv) ..
                  " (leader=" .. tostring(sLeader) .. ")  offmap=" .. tostring(bOff));
        end
    end

    print("[CSF] extra done: 额外创建 " .. tostring(iMade) .. " 个休眠城邦");
    return iMade;
end

-- 开局/读档完成后执行预留
--   预留数 = 本局城邦总数 − 地图上保留数
--     CSF_KEEP_ACTIVE_ON_MAP >= 0 → 保留数 = 该值（绝对值）
--     CSF_KEEP_ACTIVE_ON_MAP == -1 → 全留（预留 0 个，纯原版）
--     CSF_KEEP_ACTIVE_ON_MAP == -2 → 按 CSF_KEEP_ACTIVE_PERCENT 比例保留
local function CSF_ReserveCityStates()
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    local iTotal = #tIDs;
    local iDone = 0;

    -- 先算【地图上要保留几座】
    local iKeep;
    if CSF_KEEP_ACTIVE_ON_MAP == nil or CSF_KEEP_ACTIVE_ON_MAP == -1 then
        iKeep = iTotal;                                  -- 全留 = 纯原版
    elseif CSF_KEEP_ACTIVE_ON_MAP == -3 then
        -- ★ -3 模式：只藏【本模组额外造的 / 补丁兜底的】城邦，其余全留在地图上。
        --   对应设计："玩家选 N 个出现在地图上，我们额外多造 N/2 个全部休眠"。
        --   这里把 iKeep 设成"非额外城邦的数量"，下面就会正好只藏额外的那些。
        iKeep = 0;
        for _, iP in ipairs(tIDs) do
            local bEx = CSF_Safe(function()
                return Players[iP]:GetProperty("CSF_EXTRA_DORMANT");
            end);
            if bEx == nil or bEx == 0 then
                iKeep = iKeep + 1;
            end
        end
    elseif CSF_KEEP_ACTIVE_ON_MAP == -2 then
        -- 按比例。用 floor 保证"至少藏 1 个"（否则小地图上功能会静默失效）
        local iPct = CSF_KEEP_ACTIVE_PERCENT or 50;
        if iPct < 0 then iPct = 0 elseif iPct > 100 then iPct = 100 end
        iKeep = math.floor(iTotal * iPct / 100);
        if iPct < 100 and iKeep >= iTotal and iTotal > 0 then
            iKeep = iTotal - 1;                          -- 至少留 1 个可建
        end
    else
        iKeep = CSF_KEEP_ACTIVE_ON_MAP;                  -- 绝对值
    end
    if iKeep < 0 then iKeep = 0 end
    if iKeep > iTotal then iKeep = iTotal end

    local iWantReserve = iTotal - iKeep;

    -- ⭐ 排序：本模组额外造的城邦【放到最后】。
    --
    -- ⚠️ 实测教训（2026-09-27）：一开始是"优先收走它们"，结果游戏原生崩溃
    --    （EXCEPTION_ACCESS_VIOLATION，Error reading address 0x798）。
    --    原因：那些城邦是用 WorldBuilder.PlayerManager():AddPlayer() 在
    --    【地图生成阶段】新建的玩家，引擎可能没给它们建好完整状态 ——
    --    我们一杀它们的单位（CSF_SendPlayerOffMap），引擎就访问了非法内存。
    --    对照：引擎自己激活的城邦被同样处理完全没问题。
    --
    --    现在改成：它们【最后才考虑】，并且在数量足够时根本不动它们 ——
    --    让它们留在地图上当正常城邦（出生点已改成地图中部的陆地，
    --    观感与原版一致）。多出来的数量由基础城邦的休眠来提供。
    local tOrdered = {};
    local tExtra, tNormal = {}, {};
    for _, iPlayer in ipairs(tIDs) do
        local bExtra = CSF_Safe(function()
            return Players[iPlayer]:GetProperty("CSF_EXTRA_DORMANT");
        end);
        if bExtra ~= nil and bExtra ~= 0 then
            tExtra[#tExtra + 1] = iPlayer;
        else
            tNormal[#tNormal + 1] = iPlayer;
        end
    end
    -- ⭐ 排序：【带兜底标记的城邦排在最前】。
    --    它们的出生点是"CCB 放不下时救急给的"，挤在地图中部、观感差，
    --    而且本来就是为"休眠供玩家建立"而存在的 → 优先收走它们。
    --    （曾经反过来"放到最后"，结果兜底城邦全留在地图上、地图中心挤成一团。）
    for _, v in ipairs(tExtra) do tOrdered[#tOrdered + 1] = v end
    for _, v in ipairs(tNormal) do tOrdered[#tOrdered + 1] = v end
    if #tExtra > 0 then
        print("[CSF] reserve: 其中 " .. tostring(#tExtra) ..
              " 个是补丁兜底的（优先收走供建立）");
    end

    for _, iPlayer in ipairs(tOrdered) do
        if iDone >= iWantReserve then break end

        -- ⚠️ 这里【不能用 goto】—— Civ6 是 Lua 5.1，goto 是 5.2 才有的，
        --    写 goto 会让整个脚本 Syntax Error、整份 CSF_Gameplay.lua 不加载
        --    （实测踩到过，代价是休眠机制全废）。所以保留这一层 do...end。
        --
        -- ⚠️ 历史：这里曾经"硬跳过所有带标记的城邦"（因为早期用 AddPlayer 造的
        --    那些一藏就崩）。现在这些是【引擎自己创建】的基础城邦，只是出生点
        --    由补丁兜底给 —— 引擎处理后完全正常，可以安全休眠。
        --    所以跳过逻辑已移除，它们会优先被收走。
        do

            -- 已经是预留的就跳过
            if not CSF_IsReserved(iPlayer) then
                local iCities = CSF_Safe(function()
                    return Players[iPlayer]:GetCities():GetCount();
                end) or 0;

                -- 只对【还没建城】的城邦动手（已经建城的抢不回来了）
                if iCities == 0 then
                    if CSF_SendPlayerOffMap(iPlayer) then
                        m_tReserved[iPlayer] = true;
                        iDone = iDone + 1;
                    end
                end
            end
        end
    end

    print("[CSF] reserve done: " .. tostring(iDone) .. " / " .. tostring(iTotal) ..
          " city-state(s) hidden  —— 地图上保留 " .. tostring(iTotal - iDone) ..
          " 座（目标 " .. tostring(iKeep) .. "），可建 " .. tostring(iDone) .. " 座");
    return iDone;
end

-- 读档 / 开局完成时执行（赶在第 1 回合城邦建城之前）
--   ⭐ 顺序：先按原版数量正常预留（地图保持原版外观），
--           再额外造一批休眠城邦（T-144，默认关闭）。
Events.LoadScreenClose.Add(function()
    CSF_Safe(CSF_ReserveCityStates);
    CSF_Safe(CSF_CreateExtraDormantCityStates);
end);

-- 兜底：预留城邦的单位若再溜回地图，立刻清掉（保持休眠）
Events.UnitAddedToMap.Add(function(iPlayerID, iUnitID)
    if iPlayerID == nil then return end

    -- ① 预留城邦：任何上地图的单位都清掉
    if CSF_IsReserved(iPlayerID) then
        local pUnit = CSF_Safe(function() return UnitManager.GetUnit(iPlayerID, iUnitID) end);
        if pUnit ~= nil then
            local x = CSF_Safe(function() return pUnit:GetX() end) or 0;
            local y = CSF_Safe(function() return pUnit:GetY() end) or 0;
            if x >= 0 or y >= 0 then
                UnitManager.Kill(pUnit, false);
                print("[CSF] reserve: killed stray on-map unit of reserved city-state " .. tostring(iPlayerID));
            end
        end
        return;
    end

    -- ② 建邦使节：超过数量上限就直接消掉
    if CSF_MAX_ENVOYS_PER_PLAYER > 0 then
        local pUnit = CSF_Safe(function() return UnitManager.GetUnit(iPlayerID, iUnitID) end);
        if pUnit ~= nil then
            local sType = CSF_Safe(function()
                return GameInfo.Units[pUnit:GetType()].UnitType;
            end);
            if sType == "UNIT_CSF_ENVOY" then
                local iCount = CSF_CountEnvoys(iPlayerID);
                if iCount > CSF_MAX_ENVOYS_PER_PLAYER then
                    UnitManager.Kill(pUnit, false);
                    print("[CSF] cap: player " .. tostring(iPlayerID) ..
                          " already has " .. tostring(iCount - 1) ..
                          " envoy(s) (cap " .. tostring(CSF_MAX_ENVOYS_PER_PLAYER) .. "); removed the new one");
                end
            end
        end
    end
end);

-- 供 UI 手动触发（调试用）
local function CSF_ForceReserve()
    return CSF_ReserveCityStates();
end

-- ---------------------------------------------------------------------------
-- ⑧ 【混合方案】可建立城邦总表 + 按文明建邦
--
--    需求：面板要列出【全部可生成城邦】（XP2 = 48 个），而不是只列本局已有的。
--    实测约束（见 决策记录 T-69~T-86）：
--      · 本局地图只创建 N 个城邦玩家（随地图尺寸，约 10~14）
--      · 运行时可 AddPlayer 动态创建，但【上限 8 个/局】（空槽只有 54–61）
--      · 动态创建的城邦 CanReceiveInfluence=false（拿不到 CITY_STATE 等级，
--        因为等级是开局前的配置库值、运行时无 setter）
--      · 操作预分配槽（15–53）会崩游戏 —— 绝对不能碰
--
--    因此采用混合策略：
--      ★ 优先：本局已有【休眠中】的同文明玩家 → 用它（机制完整，能收使者）
--      ★ 兜底：没有则 AddPlayer 动态创建（能建城/能显示，但不能收使者，面板标注）
-- ---------------------------------------------------------------------------

-- 返回【全部可建立城邦】列表（XP2 为 48 条），每条附带"本局是否已有休眠玩家"
local function CSF_GetFoundableCityStates()
    local sRuleset = CSF_Safe(function() return GameConfiguration.GetValue("RULESET") end);
    local sDomain = "Expansion2CityStates";
    if sRuleset == "RULESET_EXPANSION_1" then
        sDomain = "Expansion1CityStates";
    elseif sRuleset ~= "RULESET_EXPANSION_2" then
        sDomain = "StandardCityStates";
    end

    local tRows = CSF_Safe(function()
        return DB.ConfigurationQuery(
            "SELECT CivilizationType, Name, Icon, CityStateCategory, Bonus, Bonus_XP1, Bonus_XP2 " ..
            "FROM CityStates WHERE Domain = ?", sDomain);
    end) or {};

    -- 本局「休眠中」的城邦玩家：CivilizationType -> playerID
    --   ⚠️⚠️ 必须排除【已派出移民、还没建城】的城邦（T-124）。
    --   原因：建邦流程是「把移民放到目标格 → 城邦在自己的回合建城」，
    --   在它建城之前 `GetCities():GetCount()` 仍是 0 —— 若不排除，
    --   同一个城邦会**继续出现在可选列表里**，玩家能再选一次，
    --   于是同一城邦拿到 2 个移民 → 建出两个城 → 出现无法正常互动的假城邦。
    --   判定方式：**地图上是否已有该城邦的单位**（休眠城邦的单位开局已被清掉）。
    local tDormant = {};
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    for _, iPlayer in ipairs(tIDs) do
        local pPlayer = Players[iPlayer];
        if pPlayer ~= nil then
            local iCities = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;
            if iCities == 0 then
                -- 地图上还有单位 → 说明已经派出去了，正在等它建城 → 不算休眠
                local bOnMap = false;
                CSF_Safe(function()
                    for _, pUnit in pPlayer:GetUnits():Members() do
                        local x = pUnit:GetX();
                        local y = pUnit:GetY();
                        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then
                            bOnMap = true;
                            break;
                        end
                    end
                end);

                if bOnMap then
                    print("[CSF] skip city-state " .. tostring(iPlayer) ..
                          " —— 已派出移民、待建城（防止重复选择）");
                else
                    local sCiv = CSF_Safe(function()
                        return PlayerConfigurations[iPlayer]:GetCivilizationTypeName();
                    end);
                    if sCiv ~= nil and tDormant[sCiv] == nil then
                        tDormant[sCiv] = iPlayer;
                    end
                end
            end
        end
    end

    -- 本局【任意】休眠城邦的数量——决定还有多少个"完整机制"的名额
    --   （有重定向策略后，只要还有任意一个休眠玩家，就能建出任意文明）
    local iDormantCount = 0;
    for _ in pairs(tDormant) do iDormantCount = iDormantCount + 1 end

    local tOut = {};
    for _, row in ipairs(tRows) do
        local iDormant = tDormant[row.CivilizationType];
        -- 机制完整性分档：
        --   "reuse"     本局已有同文明休眠玩家 → 直接复用
        --   "slot"      ★ 2026-10-06 新增：该文明有【自己的未激活预注册槽】→ 激活它
        --               这条路**不改文明** → 不崩；能用全部 54 个里的任意一个。
        --   "retarget"  借用休眠玩家改成目标文明 → ⚠️ 默认关闭（改文明 → 挂起）
        --   "dynamic"   AddPlayer 新建        → ⚠️ 默认关闭（半成品 + 崩溃风险）
        local sMode;
        if iDormant ~= nil then
            sMode = "reuse";
        elseif CSF_ENABLE_SLOT_ACTIVATION then
            -- 找该文明自己的未激活槽
            local iFree = nil;
            for j = 0, 63 do
                local pCfg = CSF_Safe(function() return PlayerConfigurations[j] end);
                if pCfg ~= nil then
                    local sThisCiv = CSF_Safe(function() return pCfg:GetCivilizationTypeName() end);
                    if sThisCiv == row.CivilizationType then
                        local bAlive = CSF_Safe(function() return Players[j]:IsAlive() end);
                        if bAlive ~= true then iFree = j; break end;
                    end
                end
            end
            if iFree ~= nil then
                sMode = "slot";
                iDormant = iFree;        -- 面板/建立函数都用 ReusePlayerID 这个字段
            else
                sMode = "unavailable";
            end
        elseif CSF_ALLOW_RETARGET then
            sMode = "retarget";          -- ⚠️ 半成品（T-109），默认关
        elseif CSF_ENABLE_DYNAMIC_CREATION then
            sMode = "dynamic";           -- ⭐ 实测正确（T-111）
        else
            sMode = "unavailable";
        end
        tOut[#tOut + 1] = {
            Civ              = row.CivilizationType,
            Name             = row.Name,
            Icon             = row.Icon,
            Category         = row.CityStateCategory,
            Bonus            = row.Bonus,
            BonusXP1         = row.Bonus_XP1,
            BonusXP2         = row.Bonus_XP2,
            ReusePlayerID    = iDormant,
            Mode             = sMode,
            -- reuse / slot / dynamic 都机制完整；retarget 是半成品，**不谎报为"完整"**。
            CanReceiveInfluence = (sMode == "reuse" or sMode == "slot" or sMode == "dynamic"),
        };
    end

    print("[CSF] foundable city-states = " .. tostring(#tOut) ..
          " (domain=" .. tostring(sDomain) ..
          ", 本局已有同文明休眠玩家 = " .. tostring(iDormantCount) ..
          " 个；retarget=" .. tostring(CSF_ALLOW_RETARGET) ..
          " slotActivate=" .. tostring(CSF_ENABLE_SLOT_ACTIVATION) ..
          " dynamic=" .. tostring(CSF_ENABLE_DYNAMIC_CREATION) .. ")");
    return tOut;
end

-- 查某文明的领袖。
--
-- ⚠️⚠️ 实测关键（T-89）：**不能**用 `GameInfo.CivilizationLeaders[civ]` 直接索引！
--     它是 userdata，直接索引**返回 nil**（实测 CIVILIZATION_ARMAGH / KANDY 都查不到）。
--     把 nil 领袖传给 `SetPlayerLeader` 会让引擎 **空指针崩溃**
--     （`EXCEPTION_ACCESS_VIOLATION` / `Error reading address 0x970`，实测崩过两次）。
--     —— 这才是前两次崩溃的真凶，跟"等级字符串"无关（T-90 修正）。
--
-- ✅ 正确做法：**遍历** `GameInfo.CivilizationLeaders()` 逐行比对 CivilizationType
--     （实测迭代 141 行、能正确匹配到 LEADER_MINOR_CIV_*）。
--     兜底：按命名规律推导 `CIVILIZATION_X -> LEADER_MINOR_CIV_X`，
--     并用 `GameInfo.Leaders[推导值] ~= nil` 验证存在性后才采用。
--   ⚠️ 本函数已【上移】到 CSF_CreateExtraDormantCityStates 之前 ——
--      Lua 的 local 必须先定义后使用，否则调用点读到的是全局 nil（审计 #9）。

-- ⚠️ 安全底线：绝不操作预分配槽（状态 5）——实测会让游戏崩溃（T-81）
local function CSF_SlotStatus(iSlot)
    local pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager() or nil;
    if pm == nil then return nil end
    local st = nil;
    pcall(function() st = pm:GetSlotStatus(iSlot) end);
    return st;
end

-- 【动态创建（AddPlayer）】开关见文件顶部配置区（必须在所有使用点之前定义）。
-- ⚠️ 注意：`CSF_ALLOW_OWN_TERRITORY` 必须在使用它的函数【之前】定义，
--    否则 Lua 读到的是全局 nil（开关会失效）。定义见文件上方配置区。

-- ---------------------------------------------------------------------------
-- 【本局城邦统计】—— 给面板用，避免把"池子大小"当成"本局城邦数"（T-145）
-- ---------------------------------------------------------------------------
--   ⚠️ 曾经踩的坑：面板提示行里写的是"本局共 48 个城邦"，而 48 是
--      `CityStates` 配置表的**池子大小**（Expansion2CityStates 域），
--      **不是本局实际有几个城邦**。本局城邦数由开局设置决定（标准 12 / 巨大 18）。
--      两者混淆会让玩家以为"本局有 48 个城邦"，进而困惑为什么只能建 7 个。
--
--   返回：{ total, dormant, active, pending, pool }
--     total   = 本局城邦玩家总数
--     dormant = 休眠中（0 城 + 地图上无单位）= **可建**
--     active  = 已建城（在地图上正常运作）
--     pending = 0 城但地图上已有单位（已派出移民、等它自己建城）
--     ⚠️ 三类必须满足 total = dormant + active + pending，否则面板数字对不上。
--        （`pending` 这一类是实测发现的：`LoadScreenClose` 刚跑完时，本局原生
--          城邦都还是 0 城但已有单位，若不单列就会让 total 对不上。）
local function CSF_GetGameCityStateStats()
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    local iTotal, iDormant, iActive, iPending = 0, 0, 0, 0;

    for _, iPlayer in ipairs(tIDs) do
        local pPlayer = Players[iPlayer];
        if pPlayer ~= nil then
            iTotal = iTotal + 1;
            local iCities = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;
            if iCities > 0 then
                iActive = iActive + 1;
            else
                -- 0 城：再看地图上有没有单位（T-124 的判定口径）
                local bOnMap = false;
                CSF_Safe(function()
                    for _, pUnit in pPlayer:GetUnits():Members() do
                        local x = CSF_Safe(function() return pUnit:GetX() end);
                        local y = CSF_Safe(function() return pUnit:GetY() end);
                        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then
                            bOnMap = true;
                            break
                        end
                    end
                end);
                if bOnMap then
                    iPending = iPending + 1;      -- 已派出、待建城
                else
                    iDormant = iDormant + 1;      -- 真休眠 = 可建
                end
            end
        end
    end

    -- 池子大小（供参考，不要当成"本局城邦数"）
    local sRuleset = CSF_Safe(function() return GameConfiguration.GetValue("RULESET") end);
    local sDomain = "Expansion2CityStates";
    if sRuleset == "RULESET_EXPANSION_1" then
        sDomain = "Expansion1CityStates";
    elseif sRuleset ~= "RULESET_EXPANSION_2" then
        sDomain = "StandardCityStates";
    end
    local tPool = CSF_Safe(function()
        return DB.ConfigurationQuery("SELECT CivilizationType FROM CityStates WHERE Domain = ?", sDomain);
    end) or {};

    return {
        total   = iTotal,
        dormant = iDormant,
        active  = iActive,
        pending = iPending,
        pool    = #tPool,
    };
end

-- 【混合建邦】按文明建邦：
--   返回 (ok, reason, iCityStatePlayerID, bFullMechanics)
--
--   三级策略（从最安全到最有风险）：
--     ①【复用】本局已有的休眠同文明玩家  —— 最安全，机制完整
--     ②【重定向】把本局【任意一个】休眠城邦玩家改成目标文明 —— 同样安全！
--        关键洞察：`SetPlayerLeader` 可以作用在**已存在的玩家**上，
--        而被改的玩家是引擎【完整初始化】过的（等级=CITY_STATE、颜色、队伍、国库都对），
--        因此完全没有 `AddPlayer` 那种"半成品玩家"的问题。
--        → 相当于把"8 个固定城邦"变成"48 选 8"，且只用已验证的 API。
--     ③【新建】AddPlayer 动态创建 —— 兜底；仅当上面两条都用尽时才走，
--        且受 CSF_ENABLE_DYNAMIC_CREATION 开关控制。
-- ===========================================================================
-- ★ 建【副本】：目标文明本局已被占用时，再建一个"能力相同、名字不同"的城邦
-- ===========================================================================
-- 需求来源（用户）：城邦池里每一个城邦都应该能在场上建出来，包括【本局已上场】的
--   —— 已上场的就再建一个副本，能力相同、名字加后缀（" II" / " III"）。
--
-- 手法来源：CCB MirrorMap 的 MirrorSyncCityStateTemplates
--   （ChineseCiv6BalanceMirrorMapDemo\Data\BBS Maps\Utility\MirrorMapDemo_SpawnPatches.lua:437）
--   它把源城邦的 CivilizationType / LeaderType 直接拷到另一个槽上，
--   于是两个槽共用同一个文明 —— 即"两个能力一样的城邦"。
--   名字差异由 UI 层拼后缀（UI\MirrorMapDemo_CityStatesPatch.lua:26
--   MirrorMapDemo_AppendDirectionalSuffix），Gameplay 侧只存标记。
--
-- ⚠️ 与 MirrorMap 的关键差别：它在【地图生成阶段】改（引擎初始化玩家之前），
--    所以颜色/名字/特性都对。我们在【对局中】改，引擎【不会】重跑初始化 ——
--    这正是当年 CSF_ALLOW_RETARGET 分支造出"半成品"（颜色不对、名字是旧名）的原因。
--
-- ⭐ 解法：改完文明后【显式重新初始化】：
--      UninitializePlayer  →  SetPlayerLeader(新文明)  →
--      SetPlayerSlotStatus(1)  →  InitializePlayer
--    （后两步的依据：引擎 FUN_180617370 只在槽位状态 ∈ {0,1,3} 时才真正初始化；
--      预注册城邦槽的状态是 5，会被静默拒绝。逆向详见
--      docs/DLL实时激活城邦_逆向进展.md §9）
--
-- ⚠️ 建城【不用】Cities:Create —— 见 T-123：Create 在间距/地形不满足时静默失败
--    并永久损坏该城邦。改为放 UNIT_SETTLER 让引擎自建。
-- ===========================================================================
local function CSF_NextCopySuffix(iSlot)
    -- 数一下这个文明已经建了几个副本 → " II" / " III" / …
    local iN = 0;
    CSF_Safe(function()
        for i = 0, 63 do
            local sCopyMark = Game:GetProperty("CSF_CopyOf_" .. tostring(i));
            if sCopyMark ~= nil then iN = iN + 1 end
        end
    end);
    local tRoman = { "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" };
    local sSuffixNew = tRoman[iN + 1] or ("x" .. tostring(iN + 2));   -- ★ tRoman 是 1 起始，iN 从 0 起
    return " " .. sSuffixNew;
end

local function CSF_FoundCityStateCopy(sCiv, iX, iY, iUnitID, iOwnerID)
    -- 目标文明本局已被占用 → 找一个新的槽，设成【同一个文明】，再建一个
    local pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager() or nil;
    if pm == nil then return false, "no_worldbuilder" end;

    local sLeader = CSF_GetLeaderForCiv(sCiv);
    if sLeader == nil then
        print("[CSF] copy: 找不到 " .. tostring(sCiv) .. " 的领袖 -> 放弃");
        return false, "no_leader";
    end

    -- ① 先验证地点（T-118：验证在创建玩家之前，避免留下孤儿）
    local bPre, sPre = CSF_IsValidFoundLocation(iX, iY, iOwnerID);
    if not bPre then
        print("[CSF] copy: 地点不合法（" .. tostring(sPre) .. "）");
        return false, sPre;
    end

    -- ② 找一个【同类别】的休眠槽并释放它
    --    同类别才能拿到正确的 front 颜色（6 个类别对应 6 个 front 值，实测）
    local sTargetCat = nil;
    CSF_Safe(function()
        local tRows = DB.ConfigurationQuery(
            "SELECT CivilizationType, CityStateCategory FROM CityStates");
        if type(tRows) == "table" then
            for _, r in ipairs(tRows) do
                if r.CivilizationType == sCiv then sTargetCat = r.CityStateCategory end
            end
        end
    end);

    local tDormant = {};
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    for _, iPlayer in ipairs(tIDs) do
        local pPlayer = Players[iPlayer];
        if pPlayer ~= nil then
            local iCities = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;
            if iCities == 0 then
                local bOnMap = false;
                CSF_Safe(function()
                    for _, pUnit in pPlayer:GetUnits():Members() do
                        local x, y = pUnit:GetX(), pUnit:GetY();
                        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then bOnMap = true break end
                    end
                end);
                if not bOnMap then
                    local sThis = CSF_Safe(function()
                        return PlayerConfigurations[iPlayer]:GetCivilizationTypeName();
                    end);
                    local sCat = nil;
                    CSF_Safe(function()
                        local tRows = DB.ConfigurationQuery(
                            "SELECT CityStateCategory FROM CityStates WHERE CivilizationType='" ..
                            tostring(sThis) .. "'");
                        if type(tRows) == "table" and tRows[1] ~= nil then
                            sCat = tRows[1].CityStateCategory;
                        end
                    end);
                    tDormant[#tDormant + 1] = { ID = iPlayer, Civ = sThis, Cat = sCat };
                end
            end
        end
    end

    local iVictim = nil;
    for _, k in ipairs(tDormant) do
        if iVictim == nil and sTargetCat ~= nil and k.Cat == sTargetCat then iVictim = k.ID end
    end
    if iVictim == nil then
        for _, k in ipairs(tDormant) do if iVictim == nil then iVictim = k.ID end end
    end
    if iVictim == nil then
        print("[CSF] copy: 没有可复用的休眠槽（池子已用尽）");
        return false, "no_free_slot";
    end
    print("[CSF] copy: 复用休眠槽 " .. tostring(iVictim) .. " 作副本，目标类别=" ..
          tostring(sTargetCat));

    -- ③ ★★ 核心：释放休眠槽 → AddPlayer 拿回它 → 改文明（顺序不可换）
    --
    --   ⚠️⚠️⚠️ 2026-10-04 修正：**绝对不要用 SetPlayerSlotStatus + InitializePlayer！**
    --      那条路实测会让游戏在【点下一回合】时原生崩溃（无 Lua 报错、无转储）。
    --      原因：InitializePlayer 是"手工初始化一个已存在的槽"，玩家处于
    --      "引擎认为已存在、但 AI 数据不全"的状态，AI 回合处理时踩空。
    --
    --      正确做法（本文件 1519-1596 行早已验证过的流程）：
    --        UninitializePlayer(休眠槽)  →  AddPlayer(true)  →  SetPlayerLeader
    --        →  SetRandomMinorStartingPosition  →  放 UNIT_SETTLER
    --      这样玩家是引擎【新建】的，初始化完整；而且拿回的是"开局就存在"的槽，
    --      UI 的颜色表认识它（否则旗标取不到颜色）。
    pcall(function() pm:UninitializePlayer(iVictim) end);

    -- ⭐ 用 AddPlayer 把那个槽【重新拿回来】（这一步不能省！）
    local iNew = nil;
    pcall(function() iNew = pm:AddPlayer(true) end);
    if iNew == nil or iNew == -1 then
        print("[CSF] copy: AddPlayer 失败（空槽可能已用尽）");
        return false, "no_free_slot";
    end
    if iNew ~= iVictim then
        print("[CSF] copy: NOTE 拿到的槽 " .. tostring(iNew) ..
              " 不同于释放的槽 " .. tostring(iVictim) .. "（颜色可能仍缺失）");
    end
    iVictim = iNew;

    local bSet = pcall(function()
        pm:SetPlayerLeader(iVictim, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE");
    end);
    if not bSet then
        print("[CSF] copy: SetPlayerLeader 失败");
        return false, "set_leader_failed";
    end

    -- ④ 补起始位置（DLL 提示："Players without start positions will be removed."）
    pcall(function() pm:SetRandomMinorStartingPosition(iVictim) end);

    -- ④b ★★★ 2026-10-04：**用 DLL 完整激活**（这一步以前完全没有！）
    --
    --   为什么必需：`SetPlayerLeader` 只是把文明/领袖**写在配置上**，
    --   游戏侧玩家对象并没有被创建和初始化。引擎开局的激活链
    --   （FUN_180228580 → FUN_1802f9350，16 个子系统）从不经过 Lua。
    --   实测：不做这一步时，造出的副本玩家 IsAlive=false、Diplomacy=nil，
    --   点下一回合 AI 处理时**原生崩溃**。
    if C6FW ~= nil and C6FW.ActivatePlayer ~= nil then
        local okA, rA = pcall(C6FW.ActivatePlayer, iVictim);
        print("[CSF] copy: DLL 激活 ok=" .. tostring(okA) .. " 返回=" .. tostring(rA));
        pcall(function() pm:SetPlayerSlotStatus(iVictim, CSF_SLOT_AI) end);
        if C6FW.SetAlive ~= nil then
            local okS, rS = pcall(C6FW.SetAlive, iVictim, 1);
            print("[CSF] copy: SetAlive ok=" .. tostring(okS) .. " 返回=" .. tostring(rS));
        end
    else
        print("[CSF] ⛔ copy: C6FW.ActivatePlayer 不可用 —— 拒绝造副本。");
        print("[CSF]    原因：只设文明/领袖而不做完整激活，点下一回合会崩游戏。");
        return false, "no_dll";
    end

    -- ⑤ 复查：文明 / 领袖 / 等级 三项都要对
    local sGotCiv = CSF_Safe(function()
        return PlayerConfigurations[iVictim]:GetCivilizationTypeName() end);
    local sGotLdr = CSF_Safe(function()
        return PlayerConfigurations[iVictim]:GetLeaderTypeName() end);
    local sGotLvl = CSF_Safe(function()
        return PlayerConfigurations[iVictim]:GetCivilizationLevelTypeName() end);
    print("[CSF] copy 复查: civ=" .. tostring(sGotCiv) .. " leader=" .. tostring(sGotLdr) ..
          " level=" .. tostring(sGotLvl));
    if sGotCiv ~= sCiv then
        print("[CSF] copy: 文明没设上（得到 " .. tostring(sGotCiv) .. "）→ 放弃");
        return false, "civ_mismatch";
    end

    -- ⑥ 存副本标记（UI 层据此拼名字后缀）
    local sSuffix = CSF_NextCopySuffix(iVictim);
    pcall(function() Game:SetProperty("CSF_CopyOf_" .. tostring(iVictim), sCiv) end);
    pcall(function() Game:SetProperty("CSF_CopySuffix_" .. tostring(iVictim), sSuffix) end);
    print("[CSF] copy: 标记 " .. tostring(iVictim) .. " 为 " .. tostring(sCiv) ..
          " 的副本，后缀=" .. tostring(sSuffix));

    -- ⑦ 建城（T-123：放移民让引擎自建，不用 Cities:Create）
    if m_tReserved[iVictim] then
        m_tReserved[iVictim] = nil;
        print("[CSF] copy: 解除 " .. tostring(iVictim) .. " 的预留标记");
    end
    local bUnit = pcall(function()
        UnitManager.InitUnit(iVictim, "UNIT_SETTLER", iX, iY);
    end);
    print("[CSF] copy: 放移民到 (" .. tostring(iX) .. "," .. tostring(iY) ..
          ") ok=" .. tostring(bUnit));
    if not bUnit then
        m_tReserved[iVictim] = true;
        return false, "settler_failed", iVictim, true;
    end
    CSF_ConsumeEnvoy(iX, iY, iUnitID, iOwnerID);
    print("[CSF] copy: 副本 " .. tostring(iVictim) .. "（" .. tostring(sCiv) ..
          tostring(sSuffix) .. "）的移民已就位，将在它的回合自行建城");
    return true, "ok", iVictim, true;
end

local function CSF_FoundCityStateByCiv(sCiv, iX, iY, iUnitID, iOwnerID)
    if sCiv == nil or iX == nil or iY == nil then
        return false, "bad_args";
    end

    -- 先把【本局所有休眠城邦玩家】列出来（0 城 = 还没建城）
    --   ⚠️ 同样要排除【已派出移民、待建城】的（T-124，防重复建邦）
    local tDormant = {};
    local tIDs = CSF_Safe(function() return PlayerManager.GetAliveMinorIDs() end) or {};
    for _, iPlayer in ipairs(tIDs) do
        local pPlayer = Players[iPlayer];
        if pPlayer ~= nil then
            local iCities = CSF_Safe(function() return pPlayer:GetCities():GetCount() end) or 0;
            if iCities == 0 then
                local bOnMap = false;
                CSF_Safe(function()
                    for _, pUnit in pPlayer:GetUnits():Members() do
                        local x = pUnit:GetX();
                        local y = pUnit:GetY();
                        if x ~= nil and y ~= nil and x >= 0 and y >= 0 then
                            bOnMap = true;
                            break;
                        end
                    end
                end);
                if not bOnMap then
                    local sThis = CSF_Safe(function()
                        return PlayerConfigurations[iPlayer]:GetCivilizationTypeName();
                    end);
                    tDormant[#tDormant + 1] = { ID = iPlayer, Civ = sThis };
                end
            end
        end
    end
    print("[CSF] city-state strategy: " .. tostring(#tDormant) .. " dormant player(s) available");

    -- ①【复用】同文明的休眠玩家
    local iReuse = nil;
    for _, k in ipairs(tDormant) do
        if k.Civ == sCiv and iReuse == nil then iReuse = k.ID end
    end

    -- ②【重定向】任意一个休眠玩家 → 改成目标文明
    --    ⚠️⚠️ 默认【关闭】！实测证明这条路径会造出半成品城邦
    --        （颜色不对、宗主加成不生效、UI 名字是旧名），且出现过引擎级崩溃。
    --        详见文件下方 CSF_ALLOW_RETARGET 的说明（T-109）。
    if iReuse == nil and #tDormant > 0 and CSF_ALLOW_RETARGET then
        local pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager() or nil;
        local sLeader = CSF_GetLeaderForCiv(sCiv);
        if pm ~= nil and sLeader ~= nil then
            local kVictim  = tDormant[1];
            local sOldCiv    = kVictim.Civ;
            local sOldLeader = CSF_Safe(function()
                return PlayerConfigurations[kVictim.ID]:GetLeaderTypeName();
            end);
            print("[CSF] retarget: 把休眠城邦玩家 " .. tostring(kVictim.ID) ..
                  "（原为 " .. tostring(sOldCiv) .. "）改成 " .. tostring(sCiv));

            local bSet = pcall(function()
                pm:SetPlayerLeader(kVictim.ID, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE");
            end);

            -- ⚠️ 复查【文明 + 领袖 + 等级】三项，任何一项不对就【回滚】。
            --    理由：SetPlayerLeader 若只改了一半，玩家会处于不一致状态，
            --    后续引擎处理时可能出问题。宁可完全还原，也不留半成品。
            local sNowCiv    = CSF_Safe(function()
                return PlayerConfigurations[kVictim.ID]:GetCivilizationTypeName();
            end);
            local sNowLeader = CSF_Safe(function()
                return PlayerConfigurations[kVictim.ID]:GetLeaderTypeName();
            end);
            local sNowLevel  = CSF_Safe(function()
                return PlayerConfigurations[kVictim.ID]:GetCivilizationLevelTypeName();
            end);
            print("[CSF] retarget result: civ=" .. tostring(sNowCiv) ..
                  " leader=" .. tostring(sNowLeader) .. " level=" .. tostring(sNowLevel));

            local bConsistent = bSet
                                and sNowCiv == sCiv
                                and sNowLeader == sLeader
                                and sNowLevel == "CIVILIZATION_LEVEL_CITY_STATE";

            if bConsistent then
                iReuse = kVictim.ID;
            else
                print("[CSF] retarget 结果不一致 → 尝试回滚到原文明 " .. tostring(sOldCiv));
                if sOldCiv ~= nil and sOldLeader ~= nil then
                    local bBack = pcall(function()
                        pm:SetPlayerLeader(kVictim.ID, sOldLeader, sOldCiv,
                                           "CIVILIZATION_LEVEL_CITY_STATE");
                    end);
                    local sBack = CSF_Safe(function()
                        return PlayerConfigurations[kVictim.ID]:GetCivilizationTypeName();
                    end);
                    print("[CSF] rollback ok=" .. tostring(bBack) .. " civ=" .. tostring(sBack));
                else
                    print("[CSF] 回滚信息不足（原文明/领袖读不到），跳过回滚");
                end
            end
        end
    end

    -- ★★★★★ 2026-10-06【新路径】激活「该文明自己的未激活预注册槽」
    --
    --   背景：引擎开局把**全部 54 个城邦文明**都预注册成玩家槽（status=5，未激活）。
    --         每个文明有**自己专属**的槽 → 想建哪个城邦，就激活哪个槽。
    --         这条路**不需要改文明**，所以不会触发"玩家与引擎预注册不一致"的崩溃。
    --
    --   实测（2026-10-06，DLL 修复后）：
    --     ① C6FW.ActivatePlayer(slot)         → ok
    --     ② pm:SetPlayerSlotStatus(slot, 1)   → ok（status 5 → 1）
    --     ③ C6FW.SetAlive(slot, 1)            → ok
    --     ④ 放移民                            → ok
    --     复查：IsAlive=true、GetCivType 正确、GetDiplomacy/GetInfluence 有效
    --     挂机推进 4 回合【无崩溃】，与引擎自己激活的槽状态完全同态。
    --
    --   ★ 与 reuse 的区别：reuse 只能用【本局已休眠】的少数几个；
    --     这条路能用**全部 54 个**里的任意一个（只要它的槽还没被激活）。
    --
    --   ⚠️ 前提：DLL 必须已修复 player+0x83a（initialized）与子系统写回；
    --      旧 DLL 走这条路会崩（读 NULL+0xb0 = diplomaticAI）。
    if iReuse == nil and CSF_ENABLE_SLOT_ACTIVATION then
        local iSlot = nil;
        for j = 0, 63 do
            local pCfg = CSF_Safe(function() return PlayerConfigurations[j] end);
            if pCfg ~= nil then
                local sThisCiv = CSF_Safe(function() return pCfg:GetCivilizationTypeName() end);
                if sThisCiv == sCiv then
                    local bAlive = CSF_Safe(function() return Players[j]:IsAlive() end);
                    if bAlive ~= true then iSlot = j; break end;
                end
            end
        end
        if iSlot ~= nil then
            print("[CSF] slot-activate: " .. tostring(sCiv) ..
                  " 有未激活的预注册槽 " .. tostring(iSlot) .. " → 激活它");
            -- ⚠️ 必须走 ExposedMembers 跨文件调用！
            --    `CSF_ActivateCityStateSlot` 是 CSF_CreateCityState.lua 里的**局部函数**，
            --    在本文件里是 nil —— 直接调会抛异常（实测：reason=threw）。
            --    导出名是 ExposedMembers.CSF.ActivateCityState。
            local fAct = (ExposedMembers ~= nil and ExposedMembers.CSF ~= nil)
                          and ExposedMembers.CSF.ActivateCityState or nil;
            if fAct == nil then
                print("[CSF] slot-activate: ❌ ExposedMembers.CSF.ActivateCityState 不可用");
                return false, "no_activate_fn";
            end
            local bAct = fAct(iSlot);
            if bAct == true then
                print("[CSF] slot-activate: 槽 " .. tostring(iSlot) .. " 激活成功，放移民");

                -- ⚠️⚠️⚠️ 2026-10-06 修正：**绝不能调 CSF_FoundCityState！**
                --
                --   那个函数（本文件行 552）用的是 `pPlayer:GetCities():Create(iX, iY)`，
                --   而它自己的注释（行 605）就写着：
                --       "实测崩溃日志精确停在这里：`[step] cities:Create(48,13) ...`（无 returned OK）"
                --   —— 它是**已知会崩**的旧实现。用户实测（2026-10-06）：
                --       点面板「建立」→ 日志停在 `[step] cities:Create(16,26) player=41 before=0`
                --       → 游戏直接退出，无弹窗、无转储。
                --
                --   正确做法与 reuse 分支完全一致（T-123）：
                --     ① 先解除预留标记（否则 UnitAddedToMap 会把刚放的移民当"溜回来的"杀掉）
                --     ② 放一个 UNIT_SETTLER，让城邦**自己的 AI** 建城
                --     ③ 消耗掉建邦使节
                if m_tReserved[iSlot] then
                    m_tReserved[iSlot] = nil;
                    print("[CSF] slot-activate: 解除槽 " .. tostring(iSlot) .. " 的预留标记");
                end

                -- ★★★ 放移民前的最后一道强校验（防挂起）
                --
                --   实测：InitUnit 在地图正中心（人类玩家单位密集处）会**挂起游戏**
                --   （无弹窗、无事件日志，Tuner 拒绝连接）。所以放之前再确认：
                --     ① 地块无主（GetOwner == -1）
                --     ② 地块上没有城市
                --     ③ 半径 2 内没有【任何玩家的】单位
                --
                --   ⚠️ 不能复用 FindFoundLocation 里的 tUnitPlots —— 那是**那个函数的局部变量**，
                --      在本函数里是 nil，索引它会抛异常（实测 reason=threw）。
                --      所以这里**内联**自己扫一遍单位。
                local bSafe = true;
                local pChk = CSF_Safe(function() return Map.GetPlot(iX, iY) end);
                if pChk == nil then bSafe = false end;
                if bSafe then
                    -- ⚠️⚠️ 2026-10-06 修正（用户实测：在自己领土上点建造 → unsafe_plot）：
                    --   面板用的坐标是【建邦使节所在格】，而使节通常站在**建邦者自己的领土**里
                    --   → 原来"有主就拒绝"把这种情况也挡了 → 永远失败。
                    --
                    --   实测结论：**建邦者自己的领土可以建**（仍是合法城址）；
                    --   崩的是【别人的】领土（引擎在别人的地里塞一个城邦 → 踩空）。
                    local iOwn = CSF_Safe(function() return pChk:GetOwner() end);
                    local iMine = iOwnerID; if iMine == nil then pcall(function() iMine = Game.GetLocalPlayer() end) end; if iOwn ~= nil and iOwn ~= -1 and iOwn ~= iMine then
                        bSafe = false;
                        print("[CSF] slot-activate: ⛔ 地块 (" .. tostring(iX) .. "," .. tostring(iY) ..
                              ") 属于别的玩家（" .. tostring(iOwn) .. "），拒绝建城");
                    elseif iOwn ~= nil and iOwn ~= -1 then
                        print("[CSF] slot-activate: 地块属于建邦者自己（" .. tostring(iOwn) .. "），允许");
                    end
                end
                if bSafe then
                    -- 城市检查：用 Cities 管理器（plot:GetCity 不一定存在）
                    local pCityInPlot = CSF_Safe(function() return Cities.GetCityInPlot(iX, iY) end);
                    if pCityInPlot ~= nil then
                        bSafe = false;
                        print("[CSF] slot-activate: ⛔ 地块上有城市，拒绝放移民");
                    end
                end
                if false then
                    -- ⛔ 单位检查已【停用】（2026-10-06 用户实测第二轮）
                    --
                    --   为什么停用：
                    --     · `Cities:Create` **不产生单位** → 这个检查（原本为 `InitUnit`
                    --       防挂起而加）**没有意义**；
                    --     · 而且它**误伤**：实测目标格上有别人的单位时（城邦/蛮族巡逻）
                    --       就被拒 → 用户在自己领土上也建不出来（第二次 unsafe_plot）。
                    --   ⇒ 保留代码但停用，万一将来改回 InitUnit 路线可再启用。
                    --
                    --   ⚠️⚠️ 2026-10-06 修正（用户实测：面板报 `unsafe_plot`）：
                    --   原来查"半径 2 内任何玩家的单位" → 把**建邦使节自己**也算进去了
                    --   （使节就在旁边，玩家选的格必然离它不远）→ **永远拒绝**。
                    --   而且现在用的是 `Cities:Create`（**不产生单位**），
                    --   半径检查是为 `InitUnit` 防挂起加的，**已经没有意义**。
                    local bOccupied = false;
                    local function checkPlotOccupied(tIDs)
                        CSF_Safe(function()
                            for _, iPlayer in ipairs(tIDs) do
                                -- ★ 跳过建邦者自己（iFounderOwner 或本地玩家）
                                if iPlayer ~= iMine then
                                    local pP = Players[iPlayer];
                                    if pP ~= nil then
                                        local pUnits = CSF_Safe(function() return pP:GetUnits() end);
                                        if pUnits ~= nil then
                                            pcall(function()
                                                for _, pUnit in pUnits:Members() do
                                                    local ux = CSF_Safe(function() return pUnit:GetX() end);
                                                    local uy = CSF_Safe(function() return pUnit:GetY() end);
                                                    if ux == iX and uy == iY then
                                                        bOccupied = true;
                                                    end
                                                end
                                            end);
                                        end
                                    end
                                end
                            end
                        end);
                    end
                    checkPlotOccupied(PlayerManager.GetAliveMajorIDs());
                    checkPlotOccupied(PlayerManager.GetAliveMinorIDs());
                    if bOccupied then
                        bSafe = false;
                        print("[CSF] slot-activate: ⛔ 目标格上有别的玩家的单位，拒绝建城");
                    end
                end
                if not bSafe then
                    return false, "unsafe_plot", iSlot;
                end

                -- ★★★★★ 2026-10-06【最终方案】校验通过后，**直接用 Cities:Create 建城**
                --
                --   实测对照（同一局、同样激活成功）：
                --     · 只放 UNIT_SETTLER → 挂机推进 17 回合，**城市=0**（AI 不主动建城）
                --     · 直接 Cities:Create   → **城市=1，立刻生效**（Round 11 实测）
                --
                --   所以"放移民让 AI 自建"这条路**走不通**（城邦 AI 不会主动建城）。
                --   而 Cities:Create **本身是能用的** —— 它以前崩，是因为**地块不合法**
                --   （有主 / 有城 / 单位密集）→ 引擎踩空。
                --
                --   ⇒ 正解：**先用上面那段严格校验把关，通过后再 Create。**
                --     校验已覆盖：无主 + 无城市 + 半径 2 无单位 + 非水非山 + 离边缘 ≥4。
                --
                --   ⚠️ 仍然要 pcall 包住：万一 Create 内部静默失败，至少不会把异常抛给上层。
                local bCreate, sCreateErr = pcall(function()
                    Players[iSlot]:GetCities():Create(iX, iY);
                end);
                print("[CSF] slot-activate: Cities:Create(" .. tostring(iX) .. "," .. tostring(iY) ..
                      ") player=" .. tostring(iSlot) .. " ok=" .. tostring(bCreate) ..
                      (bCreate and "" or (" err=" .. tostring(sCreateErr):sub(1,60))));

                -- 复查：Create 对非法地块会【静默失败】—— 不报错但城市数不变
                local iAfter = 0;
                pcall(function() iAfter = Players[iSlot]:GetCities():GetCount() end);
                print("[CSF] slot-activate: 建城后城市数 = " .. tostring(iAfter));
                if iAfter < 1 then
                    -- 兜底：退回"放移民"（至少让玩家看到城邦单位，AI 也许将来会建）
                    print("[CSF] slot-activate: ⚠️ Create 未生效 → 退回放移民");
                    pcall(function()
                        UnitManager.InitUnit(iSlot, "UNIT_SETTLER", iX, iY);
                    end);
                end

                CSF_ConsumeEnvoy(iX, iY, iUnitID, iOwnerID);

                print("[CSF] slot-activate: 槽 " .. tostring(iSlot) ..
                      " 建邦完成（城市数 " .. tostring(iAfter) .. "）");
                return true, "ok", iSlot, true;
            end
            print("[CSF] slot-activate: 槽 " .. tostring(iSlot) .. " 激活失败");
        else
            print("[CSF] slot-activate: " .. tostring(sCiv) .. " 没有可用的未激活槽");
        end
    end

    if iReuse ~= nil then
        print("[CSF] reuse dormant city-state player " .. tostring(iReuse) .. " for " .. tostring(sCiv));

        -- ⭐⭐ 新方案（T-123）：**不调用 `Cities:Create`，改为把该城邦的移民放到目标格，
        --    让城邦自己的 AI 建城**。
        --    为什么：`Create` 在间距/地形不满足时会【静默失败】并**永久损坏该城邦**
        --    （实测 `AliveMinors` 9→8→…、`canInf` 变 false）。而"放移民让它自建"
        --    由引擎完成建城 —— **不会失败、不会损坏、机制全对**。
        --
        --    ⚠️ 顺序关键：**必须先解除预留标记**，否则 `Events.UnitAddedToMap`
        --       会把刚放上去的移民当成"溜回地图的预留单位"立刻杀掉（实测踩到）。
        if m_tReserved[iReuse] then
            m_tReserved[iReuse] = nil;
            print("[CSF] un-reserved city-state " .. tostring(iReuse) .. " before settling");
        end

        local bUnit = pcall(function()
            UnitManager.InitUnit(iReuse, "UNIT_SETTLER", iX, iY);
        end);
        print("[CSF] settle: placed settler of player " .. tostring(iReuse) ..
              " at (" .. tostring(iX) .. "," .. tostring(iY) .. ") ok=" .. tostring(bUnit));

        if not bUnit then
            -- 放不上去 → 恢复预留标记，避免它变成"会乱跑"的城邦
            m_tReserved[iReuse] = true;
            return false, "settler_failed", iReuse, true;
        end

        -- 消耗掉用来建邦的「建邦使节」
        CSF_ConsumeEnvoy(iX, iY, iUnitID, iOwnerID);

        print("[CSF] settle: 城邦 " .. tostring(iReuse) ..
              " 的移民已就位，将在它的回合自行建城");
        return true, "ok", iReuse, true;        -- bFullMechanics = true
    end

    -- ★★ 建【副本】：走到这里说明本局没有【同文明】的休眠玩家
    --     —— 要么该文明已上场（有城），要么它的槽被别处占着。
    --     用户的最终需求：池子里任意城邦都要能建，包括已上场的（建副本）。
    if CSF_ENABLE_COPY then
        print("[CSF] 本局没有 " .. tostring(sCiv) .. " 的休眠玩家 → 尝试建副本");
        local bCopy, sCopyReason, iCopy, bCopyFull =
            CSF_FoundCityStateCopy(sCiv, iX, iY, iUnitID, iOwnerID);
        if bCopy == true then
            return true, sCopyReason, iCopy, bCopyFull;
        end
        print("[CSF] 建副本失败（" .. tostring(sCopyReason) .. "），继续走后续兜底");
    end

    -- ★ 兜底：动态创建（AddPlayer）——默认【关闭】，见上方开关说明
    if not CSF_ENABLE_DYNAMIC_CREATION then
        -- 走到这里说明：既没有同文明休眠玩家、也没有【任何】可重定向的休眠玩家
        -- → 用 `no_free_slot` 让面板提示"名额已用完"（对玩家更有意义，
        --   比"动态建邦已被关闭"这种技术说法清楚）
        print("[CSF] 没有可用的休眠城邦玩家了，且 AddPlayer 兜底已关闭；无法建立 " ..
              tostring(sCiv));
        return false, "no_free_slot";
    end

    -- ⚠️⚠️ 顺序关键：**先验证地点，再创建玩家**！
    --    原实现在验证之前就 AddPlayer，地点不合法时（例如站在别人领土上）
    --    会留下一个"活着但没有城"的【孤儿玩家】，反复点击会累积多个，
    --    卡在引擎里导致后续崩溃（实测踩到：连点两次留下玩家 54/55 后崩游戏）。
    local bPreValid, sPreReason = CSF_IsValidFoundLocation(iX, iY, iOwnerID);
    if not bPreValid then
        print("[CSF] dynamic: 地点不合法（" .. tostring(sPreReason) ..
              "），【未创建玩家】—— 请换个位置再试");
        return false, sPreReason;
    end

    -- ① 复用之前失败留下的同文明玩家（避免重复创建孤儿）
    if m_tOrphan[sCiv] ~= nil then
        local iOrphan = m_tOrphan[sCiv];
        local pOrphan = Players[iOrphan];
        if pOrphan ~= nil then
            local iC = CSF_Safe(function() return pOrphan:GetCities():GetCount() end) or 0;
            if iC == 0 then
                print("[CSF] dynamic: reuse previously created orphan player " ..
                      tostring(iOrphan) .. " for " .. tostring(sCiv));
                local bOk2, sReason2 = CSF_FoundCityState(iOrphan, iX, iY, iUnitID, iOwnerID);
                if bOk2 == true then m_tOrphan[sCiv] = nil end
                return bOk2, sReason2, iOrphan, true;
            end
        end
        m_tOrphan[sCiv] = nil;
    end

    local pm = WorldBuilder and WorldBuilder.PlayerManager and WorldBuilder.PlayerManager() or nil;
    if pm == nil then
        return false, "no_worldbuilder";
    end

    -- ⚠️ 领袖必须查得到！传 nil 会让引擎空指针崩溃（T-89）
    local sLeader = CSF_GetLeaderForCiv(sCiv);
    if sLeader == nil then
        print("[CSF] dynamic: no leader found for " .. tostring(sCiv) .. " -> abort");
        return false, "no_leader";
    end

    -- ⚠️⚠️⚠️ 【关键】先释放一个"引擎/UI 认识的槽"，再让 AddPlayer 拿回它（T-114）。
    --
    --   为什么要这样：`AddPlayer` 若拿到一个【全新槽】（54–61），那个槽
    --   **不在 UI 的颜色表里** —— 实测 `UI.GetPlayerColors(54)` 返回 `nil`，
    --   于是旗帜取不到颜色，并触发 `CityBannerManager: Called SetColor with nil value`。
    --
    --   而 `UninitializePlayer(某个休眠城邦槽)` 释放出来的槽，**会被随后的
    --   `AddPlayer` 重新拿到**（实测：释放 6 → AddPlayer 返回 6）。那些槽是
    --   **开局就存在**的，UI 的颜色表认识它们 —— 实测复用后
    --   `UI.GetPlayerColors(6)` 正常返回颜色，且 `SetColor nil` 警告消失。
    --
    --   注意：被释放的城邦**本来就是我们挑中的那个目标槽**（0 城、休眠中），
    --         所以不会额外损失本局的城邦。
    --   ⭐ 优先挑【同类别】的休眠槽 —— 因为 UI 的 front 颜色是【按城邦类别】给的
    --      （实测 6 个不同 front 值对应 6 个类别），同类别才能拿到正确颜色。
    local sTargetCat = nil;
    do
        local tRows = CSF_Safe(function()
            return DB.ConfigurationQuery(
                "SELECT CivilizationType, CityStateCategory FROM CityStates");
        end);
        if type(tRows) == "table" then
            local tCat = {};
            for _, r in ipairs(tRows) do
                if r.CivilizationType ~= nil then tCat[r.CivilizationType] = r.CityStateCategory end
            end
            sTargetCat = tCat[sCiv];
            -- 给每个休眠槽标上类别
            for _, k in ipairs(tDormant) do k.Cat = tCat[k.Civ] end
        end
    end
    print("[CSF] dynamic: 目标类别 = " .. tostring(sTargetCat));

    local iRecycled = nil;
    -- 先找同类别的
    for _, k in ipairs(tDormant) do
        if iRecycled == nil and sTargetCat ~= nil and k.Cat == sTargetCat then
            if pcall(function() pm:UninitializePlayer(k.ID) end) then iRecycled = k.ID end
        end
    end
    -- 没有同类别的再退而求其次
    if iRecycled == nil then
        for _, k in ipairs(tDormant) do
            if iRecycled == nil then
                if pcall(function() pm:UninitializePlayer(k.ID) end) then iRecycled = k.ID end
            end
        end
    end
    if iRecycled ~= nil then
        print("[CSF] dynamic: recycled dormant slot " .. tostring(iRecycled) ..
              " —— 这样新玩家才在 UI 颜色表里");
    end

    local iNew = nil;
    pcall(function() iNew = pm:AddPlayer(true) end);
    if iNew == nil or iNew == -1 then
        print("[CSF] dynamic: AddPlayer failed (空槽可能已用尽，上限 8 个)");
        return false, "no_free_slot";
    end
    if iRecycled ~= nil and iNew ~= iRecycled then
        print("[CSF] dynamic: NOTE 拿到的槽 " .. tostring(iNew) ..
              " 不同于释放的槽 " .. tostring(iRecycled) .. "（颜色可能仍缺失）");
    end

    -- ⚠️⚠️ 第 4 参数【必须传等级字符串 "CIVILIZATION_LEVEL_CITY_STATE"】！
    --     · 不传 / 传数字 → 新玩家等级为 **nil** → `CanReceiveInfluence=false`（实测）
    --     · 传字符串       → 等级为 CITY_STATE → **canInf=true**（实测验证通过）
    --     · 之前以为"传字符串会崩"，其实崩溃是【领袖为 nil】导致的（T-89/T-90 修正）
    --
    --   ⭐⭐ 顺序很关键（实测验证 T-111）：**先 SetPlayerLeader，再补起始位置**。
    --      这样引擎是在【文明已设定好之后】才把玩家补全，于是颜色 / 名字 / 特性
    --      都按【新文明】生成 —— 实测 color 与原生城邦一样是独立且正确的值。
    local bSet = pcall(function()
        pm:SetPlayerLeader(iNew, sLeader, sCiv, "CIVILIZATION_LEVEL_CITY_STATE");
    end);
    if not bSet then
        return false, "set_leader_failed";
    end

    -- ⚠️ 补一个「起始位置」。
    --    DLL 明确提示：**"Players without start positions will be removed."**
    --    —— 引擎会移除"没有起始位置的玩家"。`AddPlayer` 造出的玩家没有位置，
    --    补上之后实测 `inited=true / alive=true`，玩家才算真正完整。
    local bPos = pcall(function() pm:SetRandomMinorStartingPosition(iNew) end);
    print("[CSF] dynamic: SetRandomMinorStartingPosition(" .. tostring(iNew) ..
          ") ok=" .. tostring(bPos));

    -- 复查文明是否设上
    local sGot = CSF_Safe(function()
        return PlayerConfigurations[iNew]:GetCivilizationTypeName();
    end);
    if sGot ~= sCiv then
        print("[CSF] dynamic: civ not applied (got " .. tostring(sGot) .. ")");
        return false, "civ_mismatch";
    end

    print("[CSF] dynamic: created player " .. tostring(iNew) .. " as " .. tostring(sCiv) ..
          " (level=CITY_STATE, 可接收使者)");

    local bOk, sReason = CSF_FoundCityState(iNew, iX, iY, iUnitID, iOwnerID);
    if bOk ~= true then
        -- ⚠️ 建城失败（例如 Create 静默失败）→ 玩家已经建出来了，**登记为孤儿**。
        --    下次建同一文明时复用它，绝不再 AddPlayer 一个（避免累积导致崩溃）。
        m_tOrphan[sCiv] = iNew;
        print("[CSF] dynamic: 建城失败(" .. tostring(sReason) ..
              ")，玩家 " .. tostring(iNew) .. " 已登记为孤儿，下次复用");
    else
        m_tOrphan[sCiv] = nil;
    end
    return bOk, sReason, iNew, true;            -- 等级已验证 = CITY_STATE，机制完整
end

-- ---------------------------------------------------------------------------
-- ⑨ 【延迟执行】UI 只下单，GameCore 在游戏事件里执行
--
--    为什么要这样（实测教训 T-94）：
--      `AddPlayer` / `SetPlayerLeader` / `Cities:Create` 都是**改变引擎玩家/城市结构**
--      的重操作。如果直接在 **UI 按钮回调的调用栈内**执行，引擎此刻可能正在遍历
--      相关数据，结构被改动 → 崩溃（实测：日志停在 `dynamic: created player 54`
--      之后、`CSF_FoundCityState` 内部，界面上弹出异常框）。
--      对照实验证明：同样的函数在 tuner 上下文、在 `InGame` UI 状态里单独调用都**正常**，
--      只有"在 UI 回调栈内"会崩 —— 所以这是**调用时机问题，不是参数问题**。
--
--    做法：UI 调 `RequestFound(...)` 只把请求放进队列；
--          GameCore 在 `Events.GameCoreEventPublishComplete` 里取出来执行。
--          执行结果用 `GameEvents.CSF_FoundResult` 广播回 UI。
-- ---------------------------------------------------------------------------
local m_tPending = {};      -- 待处理的建邦请求队列
local m_kLastResult = nil;  -- 最后一次执行结果（供 UI 轮询兜底读取）
local m_iResultSeq  = 0;    -- 结果序号（UI 用来判断"有没有新结果"）

local function CSF_RequestFound(sCiv, iX, iY, iUnitID, iOwnerID)
    if sCiv == nil or iX == nil or iY == nil then
        return false;
    end
    m_tPending[#m_tPending + 1] = {
        Civ = sCiv, X = iX, Y = iY, UnitID = iUnitID, OwnerID = iOwnerID,
    };
    print("[CSF] queued found request: " .. tostring(sCiv) .. " at (" ..
          tostring(iX) .. "," .. tostring(iY) .. ") unit=" .. tostring(iUnitID) ..
          " owner=" .. tostring(iOwnerID));
    return true;
end

-- 处理队列（在游戏事件里跑，**不在 UI 回调栈内**）
local function CSF_ProcessPending()
    if #m_tPending == 0 then return end
    local tBatch = m_tPending;
    m_tPending = {};

    for _, kReq in ipairs(tBatch) do
        print("[CSF] processing queued request: " .. tostring(kReq.Civ) ..
              " at (" .. tostring(kReq.X) .. "," .. tostring(kReq.Y) .. ")");
        local bOk, sReason, iCs, bFull = false, "not_run", nil, false;
        local okCall = pcall(function()
            bOk, sReason, iCs, bFull =
                CSF_FoundCityStateByCiv(kReq.Civ, kReq.X, kReq.Y, kReq.UnitID, kReq.OwnerID);
        end);
        if not okCall then
            sReason = "threw";
            print("[CSF] ERROR: 建邦调用抛异常（已捕获，未崩游戏）");
        end
        print("[CSF] queued request result: ok=" .. tostring(bOk) ..
              " reason=" .. tostring(sReason) .. " player=" .. tostring(iCs));
        -- 存下最后结果（UI 轮询兜底用；因为某些 UI 上下文里 GameEvents 为 nil）
        m_iResultSeq = m_iResultSeq + 1;
        m_kLastResult = {
            Seq = m_iResultSeq,
            Ok = (bOk == true),
            Reason = tostring(sReason),
            Player = iCs or -1,
            X = kReq.X, Y = kReq.Y,
        };
        -- 广播回 UI（GameEvents 跨 VM；拿不到就靠上面的轮询兜底）
        pcall(function()
            GameEvents.CSF_FoundResult(bOk == true, tostring(sReason),
                                       iCs or -1, kReq.X, kReq.Y);
        end);
    end
end

-- 取最后一次结果（UI 轮询用）。返回 (seq, ok, reason, player, x, y)
local function CSF_GetLastResult()
    if m_kLastResult == nil then
        return 0, false, "none", -1, -1, -1;
    end
    return m_kLastResult.Seq, m_kLastResult.Ok, m_kLastResult.Reason,
           m_kLastResult.Player, m_kLastResult.X, m_kLastResult.Y;
end

Events.GameCoreEventPublishComplete.Add(function()
    pcall(CSF_ProcessPending);
end);

-- ---------------------------------------------------------------------------
-- 跨 VM 桥：暴露给 UI 上下文
--   （UI 与 GameCore 是两个 Lua VM，LuaEvents/GameEvents 不跨 VM）
-- ---------------------------------------------------------------------------
ExposedMembers.CSF = ExposedMembers.CSF or {};
ExposedMembers.CSF.FoundCityState      = CSF_FoundCityState;
ExposedMembers.CSF.IsValidLocation     = CSF_IsValidFoundLocation;
-- ⭐ 全地图逐级放宽的地块查找器（地图拥挤时用得上）
ExposedMembers.CSF.FindFoundLocation   = CSF_FindFoundLocation;
ExposedMembers.CSF.GetPool             = CSF_GetCityStatePool;
ExposedMembers.CSF.GetDormantCityStates = CSF_GetDormantCityStates;
ExposedMembers.CSF.ForceReserve        = CSF_ForceReserve;
ExposedMembers.CSF.IsReserved          = CSF_IsReserved;
ExposedMembers.CSF.CountEnvoys         = CSF_CountEnvoys;
ExposedMembers.CSF.MaxEnvoysPerPlayer  = CSF_MAX_ENVOYS_PER_PLAYER;
-- 【混合方案】
ExposedMembers.CSF.GetFoundableCityStates = CSF_GetFoundableCityStates;
ExposedMembers.CSF.GetGameCityStateStats = CSF_GetGameCityStateStats;
ExposedMembers.CSF.FoundCityStateByCiv    = CSF_FoundCityStateByCiv;
ExposedMembers.CSF.GetLeaderForCiv        = CSF_GetLeaderForCiv;
-- 【延迟执行】UI 用这个下单
ExposedMembers.CSF.RequestFound           = CSF_RequestFound;
-- 【结果轮询兜底】某些 UI 上下文里 GameEvents 为 nil，UI 可改用它主动拉结果
ExposedMembers.CSF.GetLastResult          = CSF_GetLastResult;

print("[CSF] CSF_Gameplay.lua ready; ExposedMembers.CSF bound" ..
      " (max envoys per player = " .. tostring(CSF_MAX_ENVOYS_PER_PLAYER) .. ")");
