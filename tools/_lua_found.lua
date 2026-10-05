local iT = 15
local pl = nil; pcall(function() pl = Players[iT] end)
if pl == nil then print("  ❌ 无玩家"); return end
local u = nil
pcall(function()
  for _, x in pl:GetUnits():Members() do
    local ut = nil
    pcall(function() ut = GameInfo.Units[x:GetType()].UnitType end)
    if ut == "UNIT_SETTLER" then u = x; break end
  end
end)
if u == nil then print("  ❌ 没有移民"); return end
local ux, uy = nil, nil
pcall(function() ux = u:GetX() end); pcall(function() uy = u:GetY() end)
print("  移民 @ (" .. tostring(ux) .. "," .. tostring(uy) .. ")")
print("  UnitOperationTypes = " .. tostring(type(UnitOperationTypes)))
print("  FOUND_CITY = " .. tostring(UnitOperationTypes ~= nil and UnitOperationTypes.FOUND_CITY or "nil"))
-- 能不能建？
local ok1, b1, t1 = pcall(function() return UnitManager.CanStartOperation(u, UnitOperationTypes.FOUND_CITY, nil, true) end)
print("  CanStartOperation ok=" .. tostring(ok1) .. " 结果=" .. tostring(b1) .. " 详情=" .. tostring(t1))
-- 直接发起
local ok2, r2 = pcall(function() return UnitManager.RequestOperation(u, UnitOperationTypes.FOUND_CITY) end)
print("  RequestOperation ok=" .. tostring(ok2) .. " 返回=" .. tostring(r2))
local cn = 0; pcall(function() cn = pl:GetCities():GetCount() end)
print("  城市数 = " .. cn)
print("  ★ 脚本正常结束")