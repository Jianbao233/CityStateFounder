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
-- ── 已知缺陷 ────────────────────────────────────────────────────────────
--   ⚠️ **颜色没绑上**：`UI.GetPlayerColors(slot)` 返回 nil。
--      但文明本身有颜色定义（`UI.GetPlayerColorValues(civType,0)` 有值）。
--      缺的是「槽位 → 颜色」的绑定，尚在追（见文档 §10.4）。
--      影响：旗标无颜色，**不影响功能**。
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

--- ⭐ 给某个槽补上颜色（需要 C6FW DLL 提供 C6FW.SetPlayerColor）。
-- 逆向依据：颜色与槽位状态是同一属性表的两个属性（getter vtable +0x58 / setter +0x130），
-- 但只有槽位状态有 Lua 包装 —— 颜色 setter 必须走 DLL。
-- @return true / false（DLL 不可用时返回 false 并打警告）
function CSF_ApplyCityStateColor(iSlot)
    -- 取该槽的颜色值：优先按【文明】取（城邦颜色是按文明定义的）
    local sCiv = nil;
    pcall(function() sCiv = PlayerConfigurations[iSlot]:GetCivilizationTypeName() end);

    -- ⚠️⚠️ 2026-10-04 修正：GetColor() 在"没颜色"时返回的是 **-1**（不是 nil、不是 0）！
    --   原代码只判 nil/0 → 于是拿着 -1 去 SetPlayerColor → 等于没补色。
    --   实测：激活后的城邦 GetColor() = -1；引擎创建的城邦有真实值。
    local function hasColor(v)
        return v ~= nil and v ~= 0 and v ~= -1 and v ~= 4294967295;
    end

    local iColor = nil;
    pcall(function() iColor = PlayerConfigurations[iSlot]:GetColor() end);

    -- ① 按【文明】取（城邦颜色是按文明定义的 —— 我们补了 PlayerColors 表，走这条）
    if not hasColor(iColor) and sCiv ~= nil and UI ~= nil
       and UI.GetPlayerColorValues ~= nil then
        local ok, iBack = pcall(function() return UI.GetPlayerColorValues(sCiv, 0) end);
        if ok and hasColor(iBack) then
            iColor = iBack;
            print("[CSF] 补色：按文明取到 " .. tostring(iColor) .. "（" .. tostring(sCiv) .. "）");
        end
    end

    -- ② 兜底：抄【场上任意一个已有颜色的城邦】
    --    为什么需要：万一 ① 取不到（UI 表在 GameCore 上下文里有时不可用），
    --    至少让旗标有个合法颜色 —— 没颜色的旗标在交互时会崩（见 CityBannerManager）。
    if not hasColor(iColor) then
        for j = 0, 63 do
            if j ~= iSlot then
                local c2, lvl = nil, nil;
                pcall(function() c2 = PlayerConfigurations[j]:GetColor() end);
                pcall(function() lvl = PlayerConfigurations[j]:GetCivilizationLevelTypeName() end);
                if lvl == "CIVILIZATION_LEVEL_CITY_STATE" and hasColor(c2) then
                    iColor = c2;
                    print("[CSF] 补色：抄同场城邦 slot " .. tostring(j)
                          .. " 的颜色 " .. tostring(iColor));
                    break;
                end
            end
        end
    end

    if not hasColor(iColor) then
        print("[CSF] 补色：取不到颜色值（" .. tostring(sCiv) .. "）");
        return false;
    end

    -- ③ 交给 DLL 写（Lua 层没有颜色的 setter）
    if C6FW == nil or C6FW.SetPlayerColor == nil then
        print("[CSF] ⚠️ 补色：C6FW.SetPlayerColor 不可用（未安装 C6FW DLL）—— "
              .. "该城邦将没有旗标颜色，交互时可能崩溃");
        return false;
    end
    local ok2, r = pcall(function()
        return C6FW.SetPlayerColor(PlayerConfigurations[iSlot], iColor);
    end);
    if ok2 and r ~= nil then
        print("[CSF] ✅ 补色成功 slot=" .. tostring(iSlot)
              .. " color=" .. tostring(iColor) .. "（" .. tostring(sCiv) .. "）");
        return true;
    end
    print("[CSF] ❌ 补色失败 slot=" .. tostring(iSlot) .. " err=" .. tostring(r));
    return false;
end

--- ⭐ 对局中实时激活一个城邦槽（池子里有、但未激活的那种）。
-- @param iSlot  目标槽号（来自 CSF_FindInactiveCityStateSlot）
-- @return true / false
function CSF_ActivateCityStateSlot(iSlot)
    local pm = nil;
    pcall(function() pm = WorldBuilder.PlayerManager() end);
    if pm == nil then return false end;
    if iSlot == nil or iSlot < 0 then return false end;

    -- ① 设槽位状态为 AI（内部枚举 1）—— 绕过 FUN_180617370 的门
    local ok1 = pcall(function() pm:SetPlayerSlotStatus(iSlot, CSF_SLOT_AI) end);
    if not ok1 then return false end;

    -- ② 初始化玩家对象
    local ok2 = pcall(function() pm:InitializePlayer(iSlot) end);
    if not ok2 then return false end;

    -- ②b ⭐ 补颜色（★ 唯一必须 DLL 的一步）
    --   引擎初始化玩家时会写「颜色」属性；我们只调 InitializePlayer 会漏掉它，
    --   后果：旗标无颜色 + 交互城邦时原生崩溃。
    --   颜色的 setter（FUN_18016b390）**没有 Lua 包装**，所以只能由 C6FW 代劳。
    CSF_ApplyCityStateColor(iSlot);

    -- ③ 复查
    local bAlive, pCities = nil, nil;
    pcall(function() bAlive = Players[iSlot]:IsAlive() end);
    pcall(function() pCities = Players[iSlot]:GetCities() end);
    if bAlive ~= true or pCities == nil then return false end;

    print("[CSF] 城邦槽 " .. tostring(iSlot) .. " 已激活（" ..
          tostring(PlayerConfigurations[iSlot]:GetCivilizationTypeName()) .. "）");
    return true;
end

--- ⭐⭐ 一站式：在 (iX, iY) 实时创建一个指定的城邦。
-- @param sCivType  目标城邦文明（如 "CIVILIZATION_LA_VENTA"）；nil = 任意一个未激活的
-- @param iX, iY    目标格
-- @return true / false
function CSF_CreateCityStateAt(sCivType, iX, iY)
    local iSlot, sCiv = CSF_FindInactiveCityStateSlot(sCivType);
    if iSlot < 0 then
        print("[CSF] 找不到可激活的城邦槽（" .. tostring(sCivType) .. "）");
        return false;
    end
    if not CSF_ActivateCityStateSlot(iSlot) then
        print("[CSF] 激活失败 slot=" .. tostring(iSlot));
        return false;
    end
    local ok, pCity = pcall(function()
        return Players[iSlot]:GetCities():Create(iX, iY);
    end);
    if not ok or pCity == nil then
        print("[CSF] 建城失败 slot=" .. tostring(iSlot));
        return false;
    end
    print("[CSF] ✅ 城邦 " .. tostring(sCiv) .. " 已建在 (" ..
          tostring(iX) .. "," .. tostring(iY) .. ")");
    return true, iSlot, sCiv;
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
