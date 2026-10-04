-- ===========================================================================
-- 在 UI 状态（state 0）里推进回合
-- ★ 逆向依据：cs_probe.py 的 endturn 探针里已有 DoEndTurn 测试
--   实测：DoEndTurn 只在 UI 状态可用（GameCore 上下文里是 nil）
-- ===========================================================================
local function try(f)
    local ok, v = pcall(f)
    if not ok then return "ERR(" .. tostring(v):sub(1, 60) .. ")" end
    if v == nil then return "nil" end
    return tostring(v)
end

print("=== UI 状态：推进回合 ===")
print("  UI                  = " .. try(function() return type(UI) end))
print("  DoEndTurn           = " .. try(function() return type(DoEndTurn) end))
print("  UI.CanEndTurn       = " .. try(function() return type(UI.CanEndTurn) end))
print("  UI.CanEndTurn()     = " .. try(function() return UI.CanEndTurn() end))
print("  Game                = " .. try(function() return type(Game) end))

if DoEndTurn ~= nil then
    for i = 1, 3 do
        print("  DoEndTurn() 第 " .. i .. " 次 -> " .. try(function() return DoEndTurn() end))
        for _ = 1, 200000 do end
    end
    print("  已尝试推进 3 次")
else
    print("  DoEndTurn 不可用，试 AutoplayManager")
    print("  AutoplayManager = " .. try(function() return type(AutoplayManager) end))
    if AutoplayManager ~= nil then
        print("  SetTurns(3)     -> " .. try(function() return AutoplayManager.SetTurns(3) end))
        print("  SetActive(true) -> " .. try(function() return AutoplayManager.SetActive(true) end))
    end
end
print("=== 结束 ===")
