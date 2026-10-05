local iMe = 0
pcall(function() iMe = Game.GetLocalPlayer() end)
-- 找一块人类单位旁边的空地
local ux, uy = -1, -1
pcall(function()
  for _, u in Players[iMe]:GetUnits():Members() do
    local x, y = nil, nil
    pcall(function() x = u:GetX() end); pcall(function() y = u:GetY() end)
    if x ~= nil and x >= 0 then ux, uy = x, y; break end
  end
end)
print("  人类单位在 (" .. tostring(ux) .. "," .. tostring(uy) .. ")")
if ux < 0 then print("  ❌ 找不到"); return end
-- 找一个相邻可走格
local tx, ty = ux, uy
pcall(function()
  for d = 0, 5 do
    local plot = Map.GetAdjacentPlot(ux, uy, d)
    if plot ~= nil and plot:IsWater() == false and plot:IsMountain() == false then
      tx, ty = plot:GetX(), plot:GetY(); return
    end
  end
end)
print("  放使节到 (" .. tostring(tx) .. "," .. tostring(ty) .. ")")
local ok, r = pcall(function() return UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", tx, ty) end)
print("  InitUnit ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
local n = 0
pcall(function() for _ in Players[iMe]:GetUnits():Members() do n = n + 1 end end)
print("  现在有 " .. n .. " 个单位")