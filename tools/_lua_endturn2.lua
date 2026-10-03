print("=== InGame 上下文里找结束回合 ===")
for _, n in ipairs({ "DoEndTurn", "EndTurn", "OnEndTurn", "RequestEndTurn", "OnNextTurn" }) do
  local v = nil
  pcall(function() v = _G[n] end)
  print(string.format("  _G[%-18s] = %s", n, type(v)))
end
print("  UI.DoEndTurn = " .. type(UI and UI.DoEndTurn))
print("  UI.EndTurn   = " .. type(UI and UI.EndTurn))
print("  GameCore_Tuner 不可用则忽略")
-- 尝试
if UI ~= nil and UI.DoEndTurn ~= nil then
  local ok, err = pcall(function() UI.DoEndTurn() end)
  print("  UI.DoEndTurn() ok=" .. tostring(ok) .. " err=" .. tostring(err))
elseif _G.DoEndTurn ~= nil then
  local ok, err = pcall(_G.DoEndTurn)
  print("  DoEndTurn() ok=" .. tostring(ok) .. " err=" .. tostring(err))
else
  print("  ⚠️ 本上下文没有结束回合函数")
end
