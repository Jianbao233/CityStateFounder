local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR" end
  return tostring(v)
end
print("  turn = " .. try(function() return Game.GetCurrentGameTurn() end))
print("  IsActive = " .. try(function() return AutoplayManager.IsActive() end))
print("  关掉挂机...")
print("  SetActive(false) = " .. try(function() return AutoplayManager.SetActive(false) end))
print("  SetTurns(0) = " .. try(function() return AutoplayManager.SetTurns(0) end))
print("  IsActive(后) = " .. try(function() return AutoplayManager.IsActive() end))