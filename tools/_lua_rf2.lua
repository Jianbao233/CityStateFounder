-- 用面板同一个来源：GetFoundableCityStates（面板日志说 2 个可用）
local t = nil
local ok, r = pcall(ExposedMembers.CSF.GetFoundableCityStates)
print("  GetFoundableCityStates ok=" .. tostring(ok) .. " 类型=" .. type(r) .. " 条目=" .. tostring(type(r)=="table" and #r or "?"))
t = r
if type(t) ~= "table" or #t == 0 then print("  ❌ 空"); return end
-- 打印前 8 条结构
for i = 1, math.min(8, #t) do
  local e = t[i]
  if type(e) == "table" then
    local parts = {}
    for k, v in pairs(e) do parts[#parts+1] = tostring(k) .. "=" .. tostring(v) end
    print("    [" .. i .. "] " .. table.concat(parts, "  "))
  else print("    [" .. i .. "] " .. tostring(e)) end
end
-- 挑第一个去建
local sCiv = nil
if type(t[1]) == "table" then sCiv = t[1].Civ or t[1].CivilizationType else sCiv = tostring(t[1]) end
print("")
print("  选第一个 = " .. tostring(sCiv))
local x, y = -1, -1
local ok2, a, b = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if ok2 then x, y = a, b end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x > 0 and sCiv ~= nil then
  local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
  local ok3, r1, r2, r3 = pcall(ExposedMembers.CSF.RequestFound, sCiv, x, y, nil, iMe)
  print("  RequestFound ok=" .. tostring(ok3) .. " 返回=" .. tostring(r1) .. "," .. tostring(r2) .. "," .. tostring(r3))
end