local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR(" .. tostring(v):sub(1,60) .. ")" end
  if v == nil then return "nil" end
  return tostring(v)
end
print("  UI.CanEndTurn()   = " .. try(function() return UI.CanEndTurn() end))
print("  UI.HasSentTurnComplete() = " .. try(function() return UI.HasSentTurnComplete() end))
print("  ActionTypes       = " .. try(function() return type(ActionTypes) end))
print("  准备调用 UI.RequestAction(1)  —— 若 ACTION_ENDTURN=1 则结束回合")
local ok, r = pcall(function() return UI.RequestAction(1) end)
print("  UI.RequestAction(1) ok=" .. tostring(ok) .. " 返回=" .. tostring(r))