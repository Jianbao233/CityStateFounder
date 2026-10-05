for _, iT in ipairs({6, 7, 8}) do
  print("  ── slot " .. iT .. " ──")
  local pc = nil; pcall(function() pc = PlayerConfigurations[iT] end)
  if pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = Players[iT]:IsAlive() end)
    print("    civ=" .. tostring(civ) .. " alive=" .. tostring(alive))
    pcall(function()
      for _, u in Players[iT]:GetUnits():Members() do
        local ux, uy, ut = nil, nil, nil
        pcall(function() ux = u:GetX() end)
        pcall(function() uy = u:GetY() end)
        pcall(function() ut = u:GetType() end)
        print(string.format("      单位 @ (%s,%s)  类型=%s", tostring(ux), tostring(uy), tostring(ut)))
      end
    end)
  end
end