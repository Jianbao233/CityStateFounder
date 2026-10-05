local function st()
  local a, b = "?", "?"
  pcall(function() a = tostring(UI.HasSentTurnComplete()) end)
  pcall(function() b = tostring(UI.CanEndTurn()) end)
  return "sent=" .. a .. " can=" .. b
end
print("  前: " .. st())
for i = 1, 5 do
  pcall(function() UI.RequestAction(1) end)
  for _ = 1, 300000 do end
end
print("  后: " .. st())
print("  UI.CanEndTurn 类型 = " .. type(UI.CanEndTurn))