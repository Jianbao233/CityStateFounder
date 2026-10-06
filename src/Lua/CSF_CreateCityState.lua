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
                    if sCivFilter == nil or sCivFilter == sCiv then
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
function CSF_ApplyCityStateColor(iSlot)
    local function hasColor(v)
        return v ~= nil and v ~= 0 and v ~= -1 and v ~= 4294967295;
    end

    local sCiv = nil;
    pcall(function() sCiv = PlayerConfigurations[iSlot]:GetCivilizationTypeName() end);

    if C6FW == nil then
        print("[CSF] ⚠️ 补色：C6FW 不可用（未安装 DLL）—— 该城邦将没有旗标颜色，交互时可能崩溃");
        return false;
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

    -- ② 找合法来源：**优先同场城邦**（用户要求：颜色复用），其次任意有色的玩家
    local iSrc, iSrcColor = -1, nil;
    local iAnySrc, iAnyColor = -1, nil;
    for j = 0, 63 do
        if j ~= iSlot then
            local c = readColor(j);
            if c ~= nil then
                if iAnySrc < 0 then iAnySrc, iAnyColor = j, c end;
                local lvl = nil;
                pcall(function() lvl = PlayerConfigurations[j]:GetCivilizationLevelTypeName() end);
                if lvl == "CIVILIZATION_LEVEL_CITY_STATE" then
                    iSrc, iSrcColor = j, c;
                    break;
                end
            end
        end
    end
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
--     ① `C6FW.ActivatePlayer(slot)`  —— 创建游戏侧玩家对象 + 16 子系统初始化
--     ② `SetPlayerSlotStatus(slot, 1)` —— 槽位状态 5 → 1（Lua 本来就能做）
--     ③ `C6FW.SetAlive(slot, 1)`       —— 置 IsAlive（写 player+0x258）
--     ④ `CSF_ApplyCityStateColor(slot)` —— 补色（尽力而为；旗标另有三级兜底）
--
--   ⚠️ 没有 C6FW 时**拒绝激活**而不是退回旧路径 —— 旧路径会崩游戏，
--      宁可"不做事"也不能"做错事"。
--
-- @param iSlot  目标槽号（来自 CSF_FindInactiveCityStateSlot）
-- @return true / false
function CSF_ActivateCityStateSlot(iSlot)
    local pm = nil;
    pcall(function() pm = WorldBuilder.PlayerManager() end);
    if pm == nil then return false end;
    if iSlot == nil or iSlot < 0 then return false end;

    -- ★ 前置检查：没有 C6FW 就不做（旧路径会崩）
    if C6FW == nil or C6FW.ActivatePlayer == nil then
        print("[CSF] ⛔ 拒绝激活 slot " .. tostring(iSlot)
              .. "：C6FW.ActivatePlayer 不可用。");
        print("[CSF]    原因：Lua 的 InitializePlayer 不会调用引擎的完整激活函数，"
              .. "激活出的玩家是半成品，点下一回合会崩游戏。");
        return false;
    end

    -- ① ★ DLL：创建游戏侧玩家对象 + 16 个子系统初始化
    local okA, rA = pcall(C6FW.ActivatePlayer, iSlot);
    if not okA or rA == nil then
        print("[CSF] ❌ ActivatePlayer 失败 slot=" .. tostring(iSlot)
              .. " err=" .. tostring(rA));
        return false;
    end

    -- ② 槽位状态 5 → 1（Lua 的 API 本来就能做）
    pcall(function() pm:SetPlayerSlotStatus(iSlot, CSF_SLOT_AI) end);

    -- ③ ★ DLL：置 IsAlive（写 player + 0x258）
    if C6FW.SetAlive ~= nil then
        local okS, rS = pcall(C6FW.SetAlive, iSlot, 1);
        if not okS or rS == nil then
            print("[CSF] ⚠️ SetAlive 失败 slot=" .. tostring(iSlot) .. "（继续尝试）");
        end
    end

    -- ④ 补色（尽力而为；旗标侧另有三级兜底，失败也不会崩）
    CSF_ApplyCityStateColor(iSlot);

    -- ⑤ 复查：三项都要对
    local bAlive, pCities, iStatus = nil, nil, nil;
    pcall(function() bAlive = Players[iSlot]:IsAlive() end);
    pcall(function() pCities = Players[iSlot]:GetCities() end);
    pcall(function() iStatus = PlayerConfigurations[iSlot]:GetSlotStatus() end);
    if bAlive ~= true or pCities == nil then
        print("[CSF] ❌ 激活复查失败 slot=" .. tostring(iSlot)
              .. " alive=" .. tostring(bAlive) .. " cities=" .. tostring(pCities ~= nil));
        return false;
    end

    print("[CSF] ✅ 城邦槽 " .. tostring(iSlot) .. " 已完整激活（"
          .. tostring(PlayerConfigurations[iSlot]:GetCivilizationTypeName())
          .. "）alive=true status=" .. tostring(iStatus));
    return true;
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
