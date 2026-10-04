print("=== 拿人类单位位置的几种方法 ===")
local u = Players[0]:GetUnits()
print("  GetUnits() = " .. type(u))
local n = 0
pcall(function() n = u:GetCount() end)
print("  单位数 = " .. tostring(n))
-- Members 给的是什么
local first = nil
pcall(function() for m in u:Members() do first = m break end end)
print("  Members() 首元素类型 = " .. type(first) .. "  值=" .. tostring(first))
-- 试 Find / GetUnit
for _, m in ipairs({ "Find", "GetUnit", "GetUnitByID", "Lookup" }) do
  print(string.format("  u[%-12s] = %s", m, type(u[m])))
end
if first ~= nil then
  local ok, r = pcall(function() return u:Find(first) end)
  print("  u:Find(" .. tostring(first) .. ") ok=" .. tostring(ok) .. " -> " .. tostring(r))
  if ok and r ~= nil then
    print("    type = " .. type(r))
    local ok2, x, y = pcall(function() return r:GetX(), r:GetY() end)
    print("    GetX/GetY ok=" .. tostring(ok2) .. " -> " .. tostring(x) .. "," .. tostring(y))
    local ok3, t = pcall(function() return r:GetType() end)
    print("    GetType = " .. tostring(ok3 and t or "ERR"))
  end
end
