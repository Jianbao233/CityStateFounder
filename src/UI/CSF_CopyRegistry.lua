-- ===========================================================================
-- CSF_CopyRegistry.lua —— 副本登记表的小工具（Gameplay 与 UI 共用）
-- ===========================================================================
-- 用途：记录"哪些玩家是某个城邦的副本"，以及副本的名字后缀。
--   Gameplay 侧写：Game:SetProperty("CSF_CopyOf_<slot>", 源文明)
--                  Game:SetProperty("CSF_CopySuffix_<slot>", " II")
--   UI 侧读：       CSF_GetGameProp("CSF_CopyOf_<slot>")
--
-- 为什么用 Game 属性而不是 Lua 全局表：
--    Gameplay（GameCore）与 UI（InGame）是**两个隔离的 Lua 上下文**，
--    userdata / 普通表都不能跨；`Game:SetProperty` / `Game:GetProperty`
--    是引擎提供的跨上下文通道（MirrorMap 用的也是这个）。
-- ===========================================================================

--- 读一个 Game 属性；失败或不存在返回 nil。
function CSF_GetGameProp(sKey)
    if sKey == nil then return nil end;
    if Game == nil or Game.GetProperty == nil then return nil end;
    local ok, v = pcall(function() return Game:GetProperty(sKey) end);
    if ok then return v end;
    return nil;
end

--- 写一个 Game 属性；成功返回 true。
function CSF_SetGameProp(sKey, vValue)
    if sKey == nil then return false end;
    if Game == nil or Game.SetProperty == nil then return false end;
    local ok = pcall(function() Game:SetProperty(sKey, vValue) end);
    return ok and true or false;
end

--- 该玩家是不是"副本"？是则返回源文明，否则 nil。
function CSF_GetCopySource(playerID)
    if playerID == nil then return nil end;
    return CSF_GetGameProp("CSF_CopyOf_" .. tostring(playerID));
end

--- 该副本的名字后缀（如 " II"）；不是副本则返回 nil。
function CSF_GetCopySuffix(playerID)
    if playerID == nil then return nil end;
    return CSF_GetGameProp("CSF_CopySuffix_" .. tostring(playerID));
end

--- 把一个城名按副本后缀加工：非副本原样返回。
function CSF_ApplyCopySuffix(sBaseName, playerID)
    local sSuffix = CSF_GetCopySuffix(playerID);
    if sBaseName == nil or sSuffix == nil or sSuffix == "" then return sBaseName end;
    local sName = tostring(sBaseName);
    -- 幂等：已经带过这个后缀就不再拼（防重复刷新时越拼越长）
    if string.sub(sName, -string.len(sSuffix)) == sSuffix then return sName end;
    return sName .. sSuffix;
end
