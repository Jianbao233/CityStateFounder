print("  RequestFound = " .. type(ExposedMembers.CSF.RequestFound))
if ExposedMembers.CSF.RequestFound == nil then print("  ❌ 不可用"); return end
-- 取一个可用的城邦
local t = nil
pcall(function() t = ExposedMembers.CSF.GetDormantCityStates() end)
local sCiv = nil
if type(t) == "table" and #t > 0 then
  for _, e in ipairs(t) do
    local c = nil
    if type(e) == "table" then c = e.Civ or e.CivilizationType else c = tostring(e) end
    -- 找场上没有的
    local bAlive = false
    for j = 0, 63 do
      local pc, pl = nil, nil
      pcall(function() pc = PlayerConfigurations[j] end); pcall(function() pl = Players[j] end)
      if pc ~= nil and pl ~= nil then
        local cv, al = nil, nil
        pcall(function() cv = pc:GetCivilizationTypeName() end)
        pcall(function() al = pl:IsAlive() end)
        if cv == c and al == true then bAlive = true break end
      end
    end
    if not bAlive then sCiv = c break end
  end
end
print("  目标 = " .. tostring(sCiv))
if sCiv == nil then print("  没有可用的"); return end
local x, y = -1, -1
local ok0, a0, b0 = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
if ok0 then x, y = a0, b0 end
print("  找地 = (" .. tostring(x) .. "," .. tostring(y) .. ")")
if x < 0 then print("  找不到地"); return end
local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
local ok, r1, r2, r3 = pcall(ExposedMembers.CSF.RequestFound, sCiv, x, y, nil, iMe)
print("  RequestFound ok=" .. tostring(ok) .. " 返回=" .. tostring(r1) .. "," .. tostring(r2) .. "," .. tostring(r3))