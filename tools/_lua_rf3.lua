-- 只挑 Mode == "reuse" 的（面板同款过滤）
local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
if type(t) ~= "table" then print("  ❌ 拿不到列表"); return end
local tReuse = {}
for _, e in ipairs(t) do
  if type(e) == "table" and e.Mode == "reuse" then tReuse[#tReuse+1] = e end
end
print("  Mode=reuse 的城邦 " .. #tReuse .. " 个:")
for i, e in ipairs(tReuse) do
  print(string.format("    [%d] %s  %s  %s", i, tostring(e.Civ), tostring(e.Category), tostring(e.Mode)))
end
if #tReuse == 0 then print("  ❌ 没有可建的"); return end
local sCiv = tReuse[1].Civ
print("")
print("  选 = " .. tostring(sCiv))
local x, y = -1, -1
local ok2, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if ok2 then x, y = a, b end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x > 0 then
  local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
  local ok3, r1 = pcall(ExposedMembers.CSF.RequestFound, sCiv, x, y, nil, iMe)
  print("  RequestFound ok=" .. tostring(ok3) .. " 返回=" .. tostring(r1))
end