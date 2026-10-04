for j = 0, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[j] end)
  if pc ~= nil then
    local c, a = nil, nil
    pcall(function() c = pc:GetCivilizationTypeName() end)
    pcall(function() a = Players[j]:IsAlive() end)
    if c == "CIVILIZATION_PRESLAV" and a == true then
      local n, col, sf = 0, nil, nil
      pcall(function() n = Players[j]:GetCities():GetCount() end)
      pcall(function() col = pc:GetColor() end)
      pcall(function() sf = Game:GetProperty("CSF_CopySuffix_" .. tostring(j)) end)
      print(string.format("  slot %2d  cities=%d  color=%s  后缀=%s", j, n, tostring(col), tostring(sf)))
    end
  end
end
