local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
print("  本地玩家 = " .. tostring(iMe))
local n = 0
pcall(function()
  for _, u in Players[iMe]:GetUnits():Members() do
    local ut, ux, uy, mv, fo = nil, nil, nil, nil, nil
    pcall(function() ut = GameInfo.Units[u:GetType()].UnitType end)
    pcall(function() ux = u:GetX() end); pcall(function() uy = u:GetY() end)
    pcall(function() mv = u:GetMovesRemaining() end)
    pcall(function() fo = u:GetFortifyTurns() end)
    n = n + 1
    print(string.format("    单位 %d: %s @ (%s,%s) 移动=%s", n, tostring(ut), tostring(ux), tostring(uy), tostring(mv)))
  end
end)
print("  人类单位数 = " .. n)
print("")
print("  CanEndTurn = " .. tostring(select(1, pcall(function() return UI.CanEndTurn() end))))
local ok, v = pcall(function() return UI.CanEndTurn() end)
print("  UI.CanEndTurn() = " .. tostring(ok and v or "ERR"))
print("  HasSentTurnComplete = " .. tostring(select(2, pcall(function() return UI.HasSentTurnComplete() end))))
local ok2, v2 = pcall(function() return UI.HasSentTurnComplete() end)
print("  UI.HasSentTurnComplete() = " .. tostring(ok2 and v2 or "ERR"))