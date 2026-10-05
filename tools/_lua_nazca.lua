local iT = 15
local pc, pl = nil, nil
pcall(function() pc = PlayerConfigurations[iT] end)
pcall(function() pl = Players[iT] end)
if pc == nil or pl == nil then print("  ❌ 槽位不存在"); return end
local alive = nil; pcall(function() alive = pl:IsAlive() end)
print("  IsAlive = " .. tostring(alive))
local x, y = -1, -1
local ok, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if ok then x, y = a, b end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x < 0 then print("  找不到地"); return end
local okU, rU = pcall(function() return UnitManager.InitUnit(iT, "UNIT_SETTLER", x, y) end)
print("  InitUnit ok=" .. tostring(okU) .. " 返回=" .. tostring(rU))
local n = 0
pcall(function() for _ in pl:GetUnits():Members() do n = n + 1 end end)
print("  单位数 = " .. n)
print("  ★ 脚本正常结束")