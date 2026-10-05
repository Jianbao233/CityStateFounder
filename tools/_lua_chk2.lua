print("CHECK C6FW=" .. type(C6FW) .. " CSF=" .. type(ExposedMembers ~= nil and ExposedMembers.CSF or nil) .. " Map=" .. type(Map))
if C6FW ~= nil then print("  ActivatePlayer=" .. type(C6FW.ActivatePlayer) .. " SetAlive=" .. type(C6FW.SetAlive)) end
local ok, t = pcall(function() return Game.GetCurrentGameTurn() end)
print("  turn=" .. tostring(t))