print("CHECK C6FW=" .. type(C6FW) .. " CSF=" .. type(ExposedMembers ~= nil and ExposedMembers.CSF or nil))
if C6FW ~= nil then print("  ActivatePlayer=" .. type(C6FW.ActivatePlayer) .. " SetAlive=" .. type(C6FW.SetAlive)) end
local ok, t = pcall(function() return Game.GetCurrentGameTurn() end)
print("  turn=" .. tostring(t))
-- 判断新代码是否加载：新版本会打印"已避开 N 个有单位的格子"
local ok2, x, y, why = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
print("  FindFoundLocation -> " .. tostring(x) .. "," .. tostring(y) .. " 原因=" .. tostring(why))