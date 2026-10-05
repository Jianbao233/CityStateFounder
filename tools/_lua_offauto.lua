local function t(f) local ok,v = pcall(f); return ok and tostring(v) or "ERR" end
print("  IsActive = " .. t(function() return AutoplayManager.IsActive() end))
pcall(function() AutoplayManager.SetActive(false) end)
pcall(function() AutoplayManager.SetTurns(0) end)
for _ = 1, 500000 do end
print("  IsActive(后) = " .. t(function() return AutoplayManager.IsActive() end))
print("  本地玩家 = " .. t(function() return Game.GetLocalPlayer() end))
print("  turn = " .. t(function() return Game.GetCurrentGameTurn() end))