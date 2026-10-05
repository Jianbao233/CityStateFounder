local tInPlay = {}
for j = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[j] end); pcall(function() pl = Players[j] end)
  if pc ~= nil and pl ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    if civ ~= nil and civ ~= "" and alive == true then tInPlay[civ] = true end
  end
end
local t = nil; pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" then
  for _, e in ipairs(t) do
    local c = e.Civ or e.CivilizationType
    if c ~= nil and tInPlay[c] ~= true then sCiv = c; break end
  end
end
print("  选中（场上没有的）= " .. tostring(sCiv))
local x, y, why = -1, -1, nil
local ok, a, b, c = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if ok then x, y, why = a, b, c end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")  " .. tostring(why))
if sCiv ~= nil and x > 0 then
  local ok2, r1, r2, r3 = pcall(ExposedMembers.CSF.FoundCityStateByCiv, sCiv, x, y, nil, nil)
  print("  FoundCityStateByCiv ok=" .. tostring(ok2) .. " 返回=" .. tostring(r1) .. "," .. tostring(r2) .. "," .. tostring(r3))
end
print("  ★ (a) 执行完毕，脚本正常结束 = 没崩")