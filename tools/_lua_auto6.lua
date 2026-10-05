local function t(f) local ok,v = pcall(f); return ok and tostring(v) or "ERR" end
print("  turn = " .. t(function() return Game.GetCurrentGameTurn() end))
print("  IsActive = " .. t(function() return AutoplayManager.IsActive() end))
pcall(function() AutoplayManager.SetActive(false) end)
print("  SetTurns(2) = " .. t(function() return AutoplayManager.SetTurns(2) end))
print("  SetActive(true) = " .. t(function() return AutoplayManager.SetActive(true) end))
print("  IsActive = " .. t(function() return AutoplayManager.IsActive() end))