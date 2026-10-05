local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR(" .. tostring(v):sub(1,60) .. ")" end
  return tostring(v)
end
print("  turn(前) = " .. try(function() return Game.GetCurrentGameTurn() end))
print("  IsActive = " .. try(function() return AutoplayManager.IsActive() end))
print("  设 3 回合...")
print("  SetTurns(3) = " .. try(function() return AutoplayManager.SetTurns(3) end))
print("  SetActive(true) = " .. try(function() return AutoplayManager.SetActive(true) end))
print("  IsActive(后) = " .. try(function() return AutoplayManager.IsActive() end))