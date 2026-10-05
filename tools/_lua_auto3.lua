local function t(f) local ok,v = pcall(f); return ok and tostring(v) or "ERR" end
print("  turn(前) = " .. t(function() return Game.GetCurrentGameTurn() end))
pcall(function() AutoplayManager.SetTurns(3) end)
pcall(function() AutoplayManager.SetActive(true) end)
print("  IsActive = " .. t(function() return AutoplayManager.IsActive() end))