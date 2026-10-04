print("=== ExposedMembers.CSF 有哪些键 ===")
if ExposedMembers ~= nil and ExposedMembers.CSF ~= nil then
  local n = 0
  for k, v in pairs(ExposedMembers.CSF) do
    n = n + 1
    if n <= 30 then print(string.format("  %-30s %s", tostring(k), type(v))) end
  end
  print("  共 " .. n .. " 个键")
else
  print("  ❌ ExposedMembers.CSF 不可用")
end
print("")
print("=== slot 15 现状 ===")
local iT = 15
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-24s %s", l, ok and tostring(v) or "ERR")) end
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("GetCities:GetCount", function() return Players[iT]:GetCities():GetCount() end)
chk("单位数", function() local n=0; for _ in Players[iT]:GetUnits():Members() do n=n+1 end; return n end)
pcall(function()
  local n = Players[iT]:GetCities():GetCount()
  for k = 0, n - 1 do
    local c = Players[iT]:GetCities():GetCityByIndex(k)
    if c ~= nil then print("  ★ 城市: " .. tostring(c:GetName()) .. " @ (" .. c:GetX() .. "," .. c:GetY() .. ")") end
  end
end)