local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR(" .. tostring(v):sub(1,50) .. ")" end
  return tostring(v)
end
print("  AutoplayManager = " .. try(function() return type(AutoplayManager) end))
print("  Automation      = " .. try(function() return type(Automation) end))
if AutoplayManager ~= nil then
  for _, m in ipairs({"SetTurns","SetActive","SetAIOnly","IsActive"}) do
    print("    AutoplayManager." .. m .. " = " .. try(function() return type(AutoplayManager[m]) end))
  end
end
print("  Game.GetCurrentGameTurn = " .. try(function() return Game.GetCurrentGameTurn() end))
print("  UI.CanEndTurn = " .. try(function() return UI.CanEndTurn() end))