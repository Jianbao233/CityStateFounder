print("=== 推进回合尝试 ===")
for _, n in ipairs({ "EndTurn", "DoEndTurn", "RequestEndTurn", "OnEndTurn" }) do
  local v = nil
  pcall(function() v = _G[n] end)
  print(string.format("  _G[%-16s] = %s", n, type(v)))
end
print("  Game.EndTurn = " .. type(Game and Game.EndTurn))
print("  Game.GetTurn = " .. tostring(Game and Game.GetTurn and Game:GetTurn()))
print("  Game.GetCurrentGameTurn = " .. tostring(Game and Game.GetCurrentGameTurn and Game:GetCurrentGameTurn()))
-- 尝试推进
local ok, err = pcall(function() Game.EndTurn() end)
print("  Game:EndTurn() ok=" .. tostring(ok) .. " err=" .. tostring(err))
