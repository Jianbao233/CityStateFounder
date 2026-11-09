-- ===========================================================================
-- CSF_CreateCityState.lua —— 对局中「实时创建指定城邦」
-- ===========================================================================
-- ⭐ 2026-10-04 实测突破：把【存档池子里、但未出现在玩家槽位】的城邦
--    在对局中实时激活，并建到地图上任意位置。
--
-- ── 三步公式（零 DLL、纯现成 Lua API）──────────────────────────────────
--   ① pm:SetPlayerSlotStatus(slot, 1)        -- 用【引擎内部枚举】1 = AI
--   ② pm:InitializePlayer(slot)              -- 真正建玩家对象
--   ③ Players[slot]:GetCities():Create(x, y) -- 建在指定格
--
-- ── 为什么之前失败（逆向结论，见 docs/DLL实时激活城邦_逆向进展.md）──────
--   引擎内部函数 FUN_180617370 有一道门：
--       uVar1 = FUN_18016a2b0(player);                       -- 取槽位状态
--       if (((uVar1 & 0xfffffffc) != 0) || (uVar1 == 2)) return;   -- 拒绝
--   预注册城邦槽的状态是 **5**，`5 & 0xfffffffc = 4 ≠ 0` → 被静默拒绝。
--   所以 InitializePlayer 看着返回 true，实际什么都没做。
--   设成 1 后通过。
--
--   ⚠️ 引擎内部枚举：0=Open 1=AI 2=Closed 3=Human 4=Observer
--      （与 Lua 层暴露的 SS_CLOSED/SS_COMPUTER/SS_OBSERVER/SS_OPEN/SS_TAKEN
--        **不是一套** —— 这是此前 SetSlotStatus "实测无效"的根因）
--
-- ── 实测证据 ────────────────────────────────────────────────────────────
--   slot 36 CIVILIZATION_LA_VENTA（拉文塔）：
--     激活前 GetSlotStatus=5 alive=false GetCities=nil
--     三步后 alive=true、cities=1、首都"拉文塔"(19,5)、人口 1、所有者 36
--   原生性：IsMajor=false、GetDiplomacy() 有效、GetInfluence() 有效
--
-- ── 已知缺陷（2026-10-07 已修）──────────────────────────────────────────
--   ✅ **颜色已绑上**：`C6FW.CopyPlayerColor(src, dst)` 从同场城邦抄色。
--      之前的根因是 DLL 里查 PlayerConfiguration 的姿势错了（索引了文明表），
--      现在统一走引擎自己的取法 `*(void**)(DAT_180b8aa78 + 0x90) + slot * 0x20`。
--      影响面：旗标颜色 = 城邦红，与官方城邦一致。
-- ===========================================================================

-- 引擎内部的槽位状态枚举（**不是** Lua 的 SS_*）
CSF_SLOT_OPEN     = 0;
CSF_SLOT_AI       = 1;
CSF_SLOT_CLOSED   = 2;
CSF_SLOT_HUMAN    = 3;
CSF_SLOT_OBSERVER = 4;

--- ★ 2026-10-15：把某个槽登记为【失败隔离】。
--
--   为什么要它：激活是**不可回滚**的（禁 `SetAlive(0)` / `UninitializePlayer` ——
--   半成品回滚是历史崩溃源）。所以"已经激活、但补色/建城失败"的槽只能：
--     ① 保持原样不动（不回滚、不造第二个孤儿）；
--     ② 用一条【可见的】存档属性把它标出来，后续所有"挑目标"的地方都跳过它，
--        不再把它当正常 reuse / slot 提交（否则会反复重复同一个失败）。
--
--   属性名 `CSF_IsolatedSlot_<slot>` 与 CSF_Gameplay.lua 里的 CSF_MarkIsolated /
--   CSF_IsolatedReason 完全同一套（两个脚本共享同一 Game 属性表）。
local function CSF_IsolateSlot(iSlot, sReason)
    if iSlot == nil or iSlot < 0 then return end
    local sKey = "CSF_IsolatedSlot_" .. tostring(iSlot);
    pcall(function() Game:SetProperty(sKey, tostring(sReason)) end);
    print("[CSF] ⚠️ 隔离槽 " .. tostring(iSlot) .. "（原因：" .. tostring(sReason) ..
          "）—— 本存档内不再把它当作正常建邦目标");
end

--- ★ 2026-10-15：读回隔离原因（nil = 没被隔离）。
local function CSF_SlotIsolatedReason(iSlot)
    if iSlot == nil or iSlot < 0 then return nil end
    local sVal = nil;
    pcall(function() sVal = Game:GetProperty("CSF_IsolatedSlot_" .. tostring(iSlot)) end);
    if sVal == nil then return nil end
    return tostring(sVal);
end

--- 找一个「池子里有、但未激活」的城邦槽。
-- @param sCivFilter  可选：只找这个文明类型
-- @return slot, civType, slotStatus   找不到返回 -1
function CSF_FindInactiveCityStateSlot(sCivFilter)
    local pm = nil;
    pcall(function() pm = WorldBuilder.PlayerManager() end);
    if pm == nil then return -1, nil, nil end;

    for i = 15, 63 do
        local p, pc = nil, nil;
        pcall(function() p = Players[i] end);
        pcall(function() pc = PlayerConfigurations[i] end);
        if p ~= nil and pc ~= nil then
            local sCiv, bAlive = nil, nil;
            pcall(function() sCiv = pc:GetCivilizationTypeName() end);
            pcall(function() bAlive = p:IsAlive() end);
            if sCiv ~= nil and sCiv ~= "" and bAlive == false then
                -- 必须是城邦文明（枚举 GameInfo 匹配，不用索引取值）
                local bIsCityState = false;
                pcall(function()
                    for row in GameInfo.Civilizations() do
                        if row.CivilizationType == sCiv
                           and row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
                            bIsCityState = true;
                            break;
                        end
                    end
                end);
                if bIsCityState then
                    -- ★ 2026-10-15：已失败隔离的槽不能再被当成"可用目标"返回。
                    --   （隔离槽通常"已激活但没建出城"，再选它只会重复同一个失败。）
                    local sIso = CSF_SlotIsolatedReason(i);
                    if sIso ~= nil then
                        print("[CSF] FindInactiveSlot: 跳过已隔离的槽 " .. tostring(i) ..
                              "（" .. tostring(sIso) .. "）");
                    elseif sCivFilter == nil or sCivFilter == sCiv then
                        -- 该文明是否已被别的【已激活】槽占用（引擎不允许重复）
                        local bUsed = false;
                        for j = 0, 63 do
                            if j ~= i then
                                local pc2 = nil;
                                pcall(function() pc2 = PlayerConfigurations[j] end);
                                if pc2 ~= nil then
                                    local c2, a2 = nil, nil;
                                    pcall(function() c2 = pc2:GetCivilizationTypeName() end);
                                    pcall(function() a2 = Players[j]:IsAlive() end);
                                    if c2 == sCiv and a2 == true then bUsed = true; break end;
                                end
                            end
                        end
                        if not bUsed then
                            local iStatus = nil;
                            pcall(function() iStatus = pm:GetSlotStatus(i) end);
                            return i, sCiv, iStatus;
                        end
                    end
                end
            end
        end
    end
    return -1, nil, nil;
end

--- ⭐ 给某个槽补上颜色（走 C6FW DLL 的 CopyPlayerColor / SetPlayerColorBySlot）。
--
-- ★★★★★ 2026-10-07【第二次修正 —— 这次是真正的根因】
--
--   之前 `C6FW.SetPlayerColorBySlot` 会**卡死游戏**。逆向查清了：
--     旧实现 cfg = FUN_1802209a0(FUN_1807d0780(), slot)  ❌
--   但 `FUN_1807d0780()` 是**文明表**，`FUN_1802209a0` 是通用 vector 取元素，
--   第二个参数是**文明索引**（FUN_180228580 里传的是 FUN_180169ee0(cfg)），
--   **不是玩家槽位**。拿槽位去索引文明表 → 越界垃圾指针 → setter 跳
--   [垃圾+0x130] → 卡死。
--
--   引擎自己的取法（FUN_180617370 / FUN_180616d30 / FUN_1806185f0 /
--   FUN_1806172d0 / FUN_180619a00 五处完全一致）：
--       mgr  = FUN_180164c20()             // 就是 `return DAT_180b8aa78;`
--       base = *(void**)(mgr + 0x90)       // PlayerConfiguration 数组基址
--       cfg  = (char*)base + slot * 0x20   // 步长 0x20，按玩家 ID 索引
--   C6FW 已按这个改好（GetPlayerColorBySlot / CopyPlayerColor /
--   SetPlayerColorBySlot 全部走正确取法）。
--
--   颜色值语义（来自 FUN_180619a00 读 Players 表 Color 列）：
--       0xffffffff = 无效/未设   0 = UNDEFINED   其它 = ColorType 索引
--
-- @return true / false（DLL 不可用时返回 false 并打警告）
function CSF_ApplyCityStateColor(iSlot, sPreferCiv)
    local function hasColor(v)
        -- ★ 2026-10-15：必须先是【number】。
        --   原来只判"不是 nil / 0 / -1 / 0xffffffff" —— 而在 Lua 里
        --   `false ~= nil`、`false ~= 0`、`false ~= -1` 全都为 true，
        --   于是布尔 false 会被当成"合法颜色" → "补色成功"可以是假的。
        return type(v) == "number" and v ~= 0 and v ~= -1 and v ~= 4294967295;
    end

    local sCiv = sPreferCiv;
    pcall(function()
        if sCiv == nil then sCiv = PlayerConfigurations[iSlot]:GetCivilizationTypeName() end
    end);
    local tCategories = {};
    if DB ~= nil and DB.ConfigurationQuery ~= nil then
        pcall(function()
            local rows = DB.ConfigurationQuery(
                "SELECT CivilizationType, CityStateCategory FROM CityStates");
            for _, row in ipairs(rows or {}) do
                tCategories[row.CivilizationType] = row.CityStateCategory;
            end
        end);
    end
    local sPreferCategory = tCategories[sCiv];

    if C6FW == nil then
        print("[CSF] ⚠️ 补色：C6FW 不可用（未安装 DLL）—— 该城邦将没有旗标颜色，交互时可能崩溃");
        return false;
    end

    -- PLAYER_COLOR_TYPE is the hash of PlayerColors.Type (e.g. the
    -- CivilizationType), not an RGBA value or a COLOR_* primary component.
    -- A zero-opening game has no other minor to copy. Use its own declared
    -- scheme rather than borrowing a major civilization's jersey.
    if sCiv ~= nil and C6FW.ColorTypeIndex ~= nil and C6FW.SetPlayerColorBySlot ~= nil and
       C6FW.GetPlayerColorBySlot ~= nil then
        local okType, colorType = pcall(C6FW.ColorTypeIndex, sCiv);
        if okType and hasColor(colorType) then
            local okSet, result = pcall(C6FW.SetPlayerColorBySlot, iSlot, colorType);
            local okRead, actual = pcall(C6FW.GetPlayerColorBySlot, iSlot);
            if okSet and okRead and result == colorType and actual == colorType then return true; end
            return false;
        end
    end

    -- ── 读色：优先 DLL（最可靠），退回 Lua 的 GetColor() ──────────────────
    local function readColor(j)
        if C6FW.GetPlayerColorBySlot ~= nil then
            local ok, r = pcall(C6FW.GetPlayerColorBySlot, j);
            if ok and hasColor(r) then return r end;
        end
        local c = nil;
        pcall(function() c = PlayerConfigurations[j]:GetColor() end);
        if hasColor(c) then return c end;
        return nil;
    end

    -- ① 自己已经有合法颜色 → 什么都不用做
    local iMine = readColor(iSlot);
    if iMine ~= nil then
        print("[CSF] 补色：slot " .. tostring(iSlot) .. " 已有颜色 " .. tostring(iMine));
        return true;
    end

    -- ② 找合法来源：同文明 > 同类别 > 任意城邦 > 任意有色玩家。
    --    这样副本/激活城邦不会因为扫描顺序而穿上别的文明或类别的配色。
    local iSrc, iSrcColor = -1, nil;
    local iCategorySrc, iCategoryColor = -1, nil;
    local iAnySrc, iAnyColor = -1, nil;
    for j = 0, 63 do
        if j ~= iSlot then
            local c = readColor(j);
            if c ~= nil then
                if iAnySrc < 0 then iAnySrc, iAnyColor = j, c end;
                local lvl = nil;
                pcall(function() lvl = PlayerConfigurations[j]:GetCivilizationLevelTypeName() end);
                if lvl == "CIVILIZATION_LEVEL_CITY_STATE" then
                    local sThisCiv = nil;
                    pcall(function() sThisCiv = PlayerConfigurations[j]:GetCivilizationTypeName() end);
                    if iSrc < 0 and sPreferCiv ~= nil and sThisCiv == sPreferCiv then
                        iSrc, iSrcColor = j, c;
                    elseif iCategorySrc < 0 and sPreferCategory ~= nil
                           and tCategories[sThisCiv] == sPreferCategory then
                        iCategorySrc, iCategoryColor = j, c;
                    end
                end
            end
        end
    end
    if iSrc < 0 and iCategorySrc >= 0 then iSrc, iSrcColor = iCategorySrc, iCategoryColor end
    if iSrc < 0 then iSrc, iSrcColor = iAnySrc, iAnyColor end;

    if iSrc < 0 then
        print("[CSF] 补色：场上找不到任何有颜色的玩家（" .. tostring(sCiv) .. "）");
        return false;
    end

    -- ③ ★ DLL 抄色：src → iSlot（读+写都在 C++ 侧，走正确 cfg 取法）
    local ok2, r2 = pcall(C6FW.CopyPlayerColor, iSrc, iSlot);
    if ok2 and hasColor(r2) then
        print("[CSF] ✅ 补色成功 slot=" .. tostring(iSlot) .. " ← slot " .. tostring(iSrc)
              .. " 颜色=" .. tostring(r2) .. "（" .. tostring(sCiv) .. "）");
        return true;
    end

    -- ④ 兜底：直接写（万一 CopyPlayerColor 没导出）
    if C6FW.SetPlayerColorBySlot ~= nil then
        local ok3, r3 = pcall(C6FW.SetPlayerColorBySlot, iSlot, iSrcColor);
        if ok3 and hasColor(r3) then
            print("[CSF] ✅ 补色成功(直接写) slot=" .. tostring(iSlot)
                  .. " 颜色=" .. tostring(r3));
            return true;
        end
    end

    print("[CSF] ❌ 补色失败 slot=" .. tostring(iSlot)
          .. " src=" .. tostring(iSrc) .. " color=" .. tostring(iSrcColor)
          .. " err=" .. tostring(r2));
    return false;
end

-- 新版 C6FW 的目标快照是只读结构验收：确认官方 alive 发布后，目标玩家
-- 确实进入全局/城邦三组分类表，且 +0xD8/+0x258/+0x83A 读回一致。
-- 旧版桥没有带 slot 参数的快照字段时保留兼容，最终仍由 Lua 访问器复查。
local function CSF_VerifyNativeActivationSnapshot(iSlot)
    if C6FW == nil or C6FW.GetPlayerSnapshot == nil then
        return true, "unavailable";
    end
    local ok, s = pcall(C6FW.GetPlayerSnapshot, iSlot);
    if (not ok) or type(s) ~= "table" then
        return false, "call_failed";
    end
    -- 旧桥的无参快照没有 target_slot 字段，不把兼容桥误判成坏快照。
    if s.target_slot == nil then
        return true, "legacy_snapshot";
    end
    local checks = {
        { "read_status", s.read_status == 0 },
        { "global_read", s.global_read_status == 0 },
        { "city_state_read", s.city_state_read_status == 0 },
        { "global_lists", s.global_list_state == 5 },
        { "city_state_lists", s.city_state_list_state == 5 },
        { "global_bad_pointers", s.global_bad_member_pointer_count == 0 },
        { "global_bad_ids", s.global_bad_member_id_count == 0 },
        { "city_state_bad_pointers", s.city_state_bad_member_pointer_count == 0 },
        { "city_state_bad_ids", s.city_state_bad_member_id_count == 0 },
        { "target_slot_valid", s.target_slot_valid == 1 and s.target_slot == iSlot },
        { "target_pointer_found", s.target_pointer_found == 1 },
        { "global_target_pointer_hits", s.global_target_pointer_hits == 2 },
        { "global_target_slot_hits", s.global_target_slot_hits == 3 },
        { "city_state_target_pointer_hits", s.city_state_target_pointer_hits == 2 },
        { "city_state_target_slot_hits", s.city_state_target_slot_hits == 3 },
        { "target_slot_id", s.target_slot_id_read == 1 and s.target_slot_id == iSlot },
        { "target_alive", s.target_alive_read == 1 and s.target_alive ~= 0 },
        { "target_initialized", s.target_initialized_read == 1 and s.target_initialized ~= 0 },
    };
    for _, c in ipairs(checks) do
        if not c[2] then
            print("[CSF] ❌ 原生快照校验失败 slot=" .. tostring(iSlot)
                  .. " field=" .. tostring(c[1]));
            return false, c[1];
        end
    end
    print("[CSF] 原生快照校验通过 slot=" .. tostring(iSlot)
          .. "（全局/城邦列表与目标成员一致）");
    return true, "ok";
end

--- ⭐⭐ 对局中实时激活一个城邦槽（池子里有、但未激活的那种）。
--
-- ★★★ 2026-10-04 重大更新：**改用 DLL 的完整激活链**。
--
--   为什么换：
--     旧实现走 `SetPlayerSlotStatus(1)` + `InitializePlayer(slot)`。
--     Lua 的 `InitializePlayer` 进的是 `FUN_1806175f0 → FUN_180617370` 那条【浅】路径，
--     它**从不调用真正的激活函数 `FUN_1802f9350`**（那个函数初始化玩家的 16 个子系统）。
--     结果：玩家对象是"半成品" —— 点下一回合 AI 处理时**原生崩溃**（实测多次）。
--
    --   新实现（DLL 补上缺的那一环）：
    --     ① `C6FW.ActivatePlayer(slot)`  —— 按官方氏族链创建、发布 alive、初始化子系统
    --     ② `SetPlayerSlotStatus(slot, 1)` —— 兼容旧桥的状态复查/同步
    --     ③ `C6FW.GetAlive(slot)`         —— 只读确认；旧桥未发布时才兜底 SetAlive
    --     ④ `CSF_ApplyCityStateColor(slot)` —— 补色（硬要求：无颜色会崩旗标渲染）
--     ⑤ 可证后置校验：IsAlive / GetCities() / 槽位状态（必须读得到且 == AI(1)）
--        / 等级（必须是 CIVILIZATION_LEVEL_CITY_STATE）—— 不能只看"没抛异常"。
--
--   ⚠️ 没有 C6FW 时**拒绝激活**而不是退回旧路径 —— 旧路径会崩游戏，
--      宁可"不做事"也不能"做错事"。
--
--   ★ 2026-10-15：①③ 的原生返回值一律**严格判 1**（契约是"成功=1，失败=0/nil"，
--     只判 nil 会把 0/false 当成功）；④ 的失败不再被忽略；任何"已经激活之后"的
--     失败都只写一条可见的隔离属性（禁 SetAlive(0)/UninitializePlayer 回滚）。
--   ★ 2026-10-15【第二次修正】：① 的失败同样隔离 —— 原生失败不代表"状态没变"
--     （失败点可能在注册/初始化链中间）；④ 的 hasColor 必须是合法 number。
--
-- @param iSlot  目标槽号（来自 CSF_FindInactiveCityStateSlot）
-- @return ok, reason
--   ★ 2026-10-15【消除假成功】改签名：`true` / `(false, 原因字符串)`。
--     原实现返回单值 true/false，调用方无法知道**为什么**失败，只能看到
--     自己兜底路径的 "no_free_slot"；面板因此把原生激活失败显示成别的原因。
--     现在：原生返回 nil / 0 / false 一律判失败，并带回可显示的原因原码。
function CSF_ActivateCityStateSlot(iSlot, iX, iY)
    local pm = nil;
    pcall(function() pm = WorldBuilder.PlayerManager() end);
    if pm == nil then
        print("[CSF] ❌ 拒绝激活：WorldBuilder.PlayerManager() 不可用");
        return false, "no_player_manager";
    end
    if iSlot == nil or iSlot < 0 then
        print("[CSF] ❌ 拒绝激活：槽号非法（" .. tostring(iSlot) .. "）");
        return false, "bad_slot";
    end

    -- ★ 前置检查：没有 C6FW 就不做（旧路径会崩）
    if C6FW == nil or C6FW.ActivatePlayer == nil then
        print("[CSF] ⛔ 拒绝激活 slot " .. tostring(iSlot)
              .. "：C6FW.ActivatePlayer 不可用。");
        print("[CSF]    原因：Lua 的 InitializePlayer 不会调用引擎的完整激活函数，"
              .. "激活出的玩家是半成品，点下一回合会崩游戏。");
        return false, "no_c6fw";
    end

    -- ① ★ DLL：创建游戏侧玩家对象 + 16 个子系统初始化
    --    ⛔ 原实现 `if not okA or rA == nil` 只判 nil —— 而 C6FW 的契约是
    --       "成功返 1，失败返 0（不 push 值 → Lua 收到 nil）"。只判 nil 时
    --       任何【非 nil 的非 1 值】都会被当成功。这里严格判 `rA == 1`。
    -- 传入最终建城坐标；C6FW 会先按官方氏族链写入玩家起始地块，
    -- 再由后续 Cities:Create 在同一坐标建城。缺坐标时保留兼容的无参调用。
    local okA, rA = pcall(C6FW.ActivatePlayer, iSlot, iX, iY);
    if (not okA) or rA ~= 1 then
        print("[CSF] ❌ ActivatePlayer 失败 slot=" .. tostring(iSlot)
              .. " ok=" .. tostring(okA) .. " ret=" .. tostring(rA)
              .. "（契约：成功=1，失败=0/nil）");
        -- ★★★★★ 2026-10-15【第二次修正】失败 ≠ "状态没变"。
        --   ActivatePlayer 是"建玩家对象 + 16 个子系统初始化"的长链，失败点可能在
        --   【链中间】（注册/初始化已经做了一部分才出错），返回 0/nil 只说明"没成功"，
        --   不说明"没动过"。所以只要【调用过】原生激活而没成功，就保守写一条隔离属性：
        --     · 不回滚（SetAlive(0)/UninitializePlayer 是历史崩溃源）；
        --     · 后续挑目标时跳过它，不再把可能是半成品的槽当干净槽重复提交。
        CSF_IsolateSlot(iSlot, "activate_player_failed");
        return false, "activate_player_failed";
    end

    -- ② 槽位状态 5 → 1（Lua 的 API 本来就能做）
    local okSt, errSt = pcall(function() pm:SetPlayerSlotStatus(iSlot, CSF_SLOT_AI) end);
    if not okSt then
        print("[CSF] ⚠️ SetPlayerSlotStatus 失败 slot=" .. tostring(iSlot)
              .. " err=" .. tostring(errSt));
    end

    -- ③ ★ alive 只读确认；新版 ActivatePlayer 已按官方氏族顺序调用
    --    0x2FA9A0(player,1)。不能无条件再调用 SetAlive(1)，否则会在
    --    16 子系统初始化之后重复清空/重建 23 张列表。只有旧桥没有发布
    --    alive 时才保留一次兼容兜底。
    local bAlivePublished = false;
    if C6FW.GetAlive ~= nil then
        local okG, rG = pcall(C6FW.GetAlive, iSlot);
        bAlivePublished = okG and rG == 1;
        print("[CSF] GetAlive 只读确认 slot=" .. tostring(iSlot)
              .. " ok=" .. tostring(okG) .. " ret=" .. tostring(rG));
    end
    if not bAlivePublished then
        if C6FW.SetAlive == nil then
            print("[CSF] ❌ 拒绝激活 slot " .. tostring(iSlot)
                  .. "：alive 未发布且 C6FW.SetAlive 不可用");
            CSF_IsolateSlot(iSlot, "no_set_alive_fn");
            return false, "no_set_alive_fn";
        end
        local okS, rS = pcall(C6FW.SetAlive, iSlot, 1);
        if (not okS) or rS ~= 1 then
            print("[CSF] ❌ SetAlive 兜底失败 slot=" .. tostring(iSlot)
                  .. " ok=" .. tostring(okS) .. " ret=" .. tostring(rS));
            CSF_IsolateSlot(iSlot, "set_alive_failed");
            return false, "set_alive_failed";
        end
        bAlivePublished = true;
    end

    -- ④ 补色。⛔ 原实现是"尽力而为"，返回值【被完全忽略】—— 但无颜色的城邦
    --    会让旗标渲染读 NULL+0xc 崩游戏（用户 2026-10-06 实测崩溃）。
    --    所以这里改成硬失败：激活已经发生、不可回滚，于是记录隔离并如实返回。
    local sTargetCiv = nil;
    pcall(function() sTargetCiv = PlayerConfigurations[iSlot]:GetCivilizationTypeName() end);
    local bColorOk = CSF_ApplyCityStateColor(iSlot, sTargetCiv);
    if bColorOk ~= true then
        print("[CSF] ❌ 补色失败 slot=" .. tostring(iSlot)
              .. " —— 该城邦没有旗标颜色，交互时会崩；已隔离该槽");
        CSF_IsolateSlot(iSlot, "no_color");
        return false, "no_color";
    end

    local bSnapshotOk, sSnapshotReason = CSF_VerifyNativeActivationSnapshot(iSlot);
    if bSnapshotOk ~= true then
        CSF_IsolateSlot(iSlot, "native_snapshot_" .. tostring(sSnapshotReason));
        return false, "native_snapshot_" .. tostring(sSnapshotReason);
    end

    -- ⑤ ★ 可证后置校验：IsAlive / 城市容器 / 槽位状态，三项都要能【读到证据】
    --    （原实现取了 iStatus 却从不用它，等于没校验状态）
    local bAlive, pCities, iStatus = nil, nil, nil;
    local iNativeStatus = nil;
    pcall(function() bAlive = Players[iSlot]:IsAlive() end);
    pcall(function() pCities = Players[iSlot]:GetCities() end);
    -- ★ 2026-10-15：状态必须用【与 setter 同一个读法】读 —— 上面写的是
    --   `pm:SetPlayerSlotStatus`，所以这里必须读 `pm:GetSlotStatus`。
    --   （原来读的是 PlayerConfigurations[slot]:GetSlotStatus()，另一个取法，
    --     而且读到的 nil 也被当成"没问题"跳过了。）
    pcall(function() iStatus = pm:GetSlotStatus(iSlot) end);
    if C6FW.GetNativeSlotStatus ~= nil then
        local okNS, rNS = pcall(C6FW.GetNativeSlotStatus, iSlot);
        if okNS then iNativeStatus = rNS end
        if (not okNS) or iNativeStatus ~= CSF_SLOT_AI then
            print("[CSF] ❌ 原生槽位状态复查失败 slot=" .. tostring(iSlot)
                  .. "：native=" .. tostring(iNativeStatus)
                  .. "（期望 " .. tostring(CSF_SLOT_AI) .. "）");
            CSF_IsolateSlot(iSlot, "native_status_wrong");
            return false, "native_status_wrong";
        end
    end
    if bAlive ~= true then
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot)
              .. "：IsAlive = " .. tostring(bAlive));
        CSF_IsolateSlot(iSlot, "post_alive_false");
        return false, "post_alive_false";
    end
    if pCities == nil then
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot) .. "：GetCities() = nil");
        CSF_IsolateSlot(iSlot, "post_no_cities");
        return false, "post_no_cities";
    end
    -- ★ 2026-10-15：状态必须【读得到】且【正好等于 CSF_SLOT_AI(1)】。
    --   原实现只在 `iStatus == 5` 时失败 —— 即 nil（读不到证据）和其它任何值
    --   都被当成"没问题"，于是"状态根本没落对"也能宣称完整激活。
    if iStatus == nil then
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot)
              .. "：pm:GetSlotStatus 读不到（nil）—— 没有状态证据就不能算激活成功");
        CSF_IsolateSlot(iSlot, "post_status_nil");
        return false, "post_status_nil";
    end
    if iStatus == 5 then
        -- 5 = 预注册城邦槽的原始状态；`FUN_180617370` 的状态门禁会静默拒绝它。
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot)
              .. "：槽位状态仍是 5（预注册未激活态，引擎会静默拒绝建城）");
        CSF_IsolateSlot(iSlot, "post_status_still_5");
        return false, "post_status_still_5";
    end
    if iStatus ~= CSF_SLOT_AI then
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot) .. "：槽位状态 = "
              .. tostring(iStatus) .. "（期望 AI = " .. tostring(CSF_SLOT_AI) .. "）");
        CSF_IsolateSlot(iSlot, "post_status_wrong");
        return false, "post_status_wrong";
    end

    local sLevel = nil;
    pcall(function() sLevel = PlayerConfigurations[iSlot]:GetCivilizationLevelTypeName() end);
    if sLevel ~= "CIVILIZATION_LEVEL_CITY_STATE" then
        -- ★ 2026-10-15：等级决定 CanReceiveInfluence（能否收使者）——等级不对
        --   机制就不完整，不能再向面板宣称"已完整激活"。
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot) .. "：等级 = "
              .. tostring(sLevel) .. "（期望 CIVILIZATION_LEVEL_CITY_STATE）");
        CSF_IsolateSlot(iSlot, "post_level_wrong");
        return false, "post_level_wrong";
    end

    print("[CSF] ✅ 城邦槽 " .. tostring(iSlot) .. " 已完整激活（"
          .. tostring(PlayerConfigurations[iSlot]:GetCivilizationTypeName())
          .. "）alive=true status=" .. tostring(iStatus)
          .. " level=" .. tostring(sLevel));
    return true, "ok";
end

--- ⚠️【已废弃，保留仅为兼容旧探针】一站式建邦请走 CSF_Gameplay.lua 的
--  `CSF_FoundCityStateByCiv`（它带完整的 3 环距离/地形校验）。
--
--  ★ 2026-10-07：**这里原来的 `UnitManager.InitUnit(...SETTLER...)` 兜底已删除。**
--    实测结论（记录在案）：`Cities:Create` 失败后再调 `InitUnit` 会**卡死/崩溃游戏**
--    （InitUnit 在"创建失败的半成品玩家"上会挂）。宁可返回 false 也不能留着这颗雷。
function CSF_CreateCityStateAt(sCivType, iX, iY)
    print("[CSF] ⚠️ CSF_CreateCityStateAt 已废弃（InitUnit 兜底会崩游戏），"
          .. "请改用 CSF_FoundCityStateByCiv。参数=" .. tostring(sCivType)
          .. " (" .. tostring(iX) .. "," .. tostring(iY) .. ")");
    return false;
end

-- 暴露给其它脚本 / 调试用
ExposedMembers = ExposedMembers or {};
ExposedMembers.CSF_CreateCityState = ExposedMembers.CSF_CreateCityState or {};
ExposedMembers.CSF_CreateCityState.CreateAt            = CSF_CreateCityStateAt;
ExposedMembers.CSF_CreateCityState.ActivateSlot        = CSF_ActivateCityStateSlot;
ExposedMembers.CSF_CreateCityState.FindInactiveSlot    = CSF_FindInactiveCityStateSlot;
-- ⚠️ 2026-10-04：原来漏了这一行 —— 补色函数一直没被导出，
--    所以外部（验收探针 / 其它脚本）调不到它。
ExposedMembers.CSF_CreateCityState.ApplyColor          = CSF_ApplyCityStateColor;

-- ⭐ 同时挂到 ExposedMembers.CSF（面板/游戏逻辑那一侧用的表），
--    这样 CSF.ActivateCityState 也能一并补色 —— 激活与补色应当成对出现。
ExposedMembers.CSF = ExposedMembers.CSF or {};
ExposedMembers.CSF.ApplyCityStateColor  = CSF_ApplyCityStateColor;
ExposedMembers.CSF.ActivateCityState    = CSF_ActivateCityStateSlot;
ExposedMembers.CSF.FindInactiveCityStateSlot = CSF_FindInactiveCityStateSlot;
ExposedMembers.CSF.CreateCityStateAt    = CSF_CreateCityStateAt;

print("[CSF] CSF_CreateCityState.lua loaded（实时创建城邦：三步公式已就绪）");
