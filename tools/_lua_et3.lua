local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR(" .. tostring(v):sub(1,50) .. ")" end
  return tostring(v)
end
print("  HasSentTurnComplete(前) = " .. try(function() return UI.HasSentTurnComplete() end))
print("  CanEndTurn              = " .. try(function() return UI.CanEndTurn() end))
print("  调 RequestAction(1)...")
pcall(function() UI.RequestAction(1) end)
for _ = 1, 500000 do end
print("  HasSentTurnComplete(后) = " .. try(function() return UI.HasSentTurnComplete() end))
print("  Network = " .. try(function() return type(Network) end))
if Network ~= nil then
  for _, m in ipairs({"SendTurnComplete","EndTurn","IsTurnComplete","GetLocalPlayerID"}) do
    print("    Network." .. m .. " = " .. try(function() return type(Network[m]) end))
  end
end
print("  Game = " .. try(function() return type(Game) end))
if Game ~= nil then
  for _, m in ipairs({"GetCurrentGameTurn","DoTurn","EndTurn","RequestEndTurn"}) do
    print("    Game." .. m .. " = " .. try(function() return type(Game[m]) end))
  end
end