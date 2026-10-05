local iMe = 0
pcall(function() iMe = Game.GetLocalPlayer() end)
print("  本地玩家 = " .. tostring(iMe))
local n = 0
pcall(function()
  for _, u in Players[iMe]:GetUnits():Members() do
    local ut, ux, uy = nil, nil, nil
    pcall(function() ut = u:GetType() end)
    pcall(function() ux = u:GetX() end)
    pcall(function() uy = u:GetY() end)
    n = n + 1
    print(string.format("    单位 %d: %s @ (%s,%s)", n, tostring(ut), tostring(ux), tostring(uy)))
  end
end)
print("  共 " .. n .. " 个单位")