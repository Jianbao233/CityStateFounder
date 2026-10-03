-- ★★★ 收尾：激活后立刻在指定位置建城
print("=== 收尾：激活 + 建城 ===")
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then print("❌ 无 PlayerManager"); return end

-- 找一个未激活的城邦槽（状态 != 1，alive=false）
local iTarget, sCiv = -1, nil
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if civ ~= nil and civ ~= "" and alive == false then
      iTarget, sCiv = i, civ
      break
    end
  end
end
if iTarget < 0 then print("❌ 没有未激活的城邦槽了（上一轮把 slot 35 激活了）"); return end
local st = nil; pcall(function() st = pm:GetSlotStatus(iTarget) end)
print(string.format("  目标: slot %d  civ=%s  GetSlotStatus=%s", iTarget, sCiv, tostring(st)))

-- ★ 两步激活
print("")
print("① SetPlayerSlotStatus(" .. iTarget .. ", 1)")
pcall(function() pm:SetPlayerSlotStatus(iTarget, 1) end)
print("② InitializePlayer(" .. iTarget .. ")")
pcall(function() pm:InitializePlayer(iTarget) end)

local alive = nil; pcall(function() alive = Players[iTarget]:IsAlive() end)
print("  → alive = " .. tostring(alive))
if alive ~= true then print("❌ 激活失败"); return end

-- ★ 找一个没主的陆地格
print("")
print("=== 找目标格（城镇中心需要无主陆地）===")
local iX, iY = -1, -1
pcall(function()
  local w, h = Map.GetGridSize()
  for y = 3, h - 4 do
    for x = 3, w - 4 do
      local plot = Map.GetPlot(x, y)
      if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
         and plot:GetFeatureType() == -1 then
        -- 邻格至少 3 块陆地，避免卡在死地
        local land = 0
        for d = 0, 5 do
          local nb = Map.GetAdjacentPlot(x, y, d)
          if nb ~= nil and nb:IsWater() == false then land = land + 1 end
        end
        if land >= 4 then iX, iY = x, y; return end
      end
    end
  end
end)
print(string.format("  目标格 (%d,%d)", iX, iY))
if iX < 0 then print("❌ 没找到合适的地块"); return end

-- ★★★ 建城
print("")
print("=== ★ GetCities():Create(" .. iX .. ", " .. iY .. ") ===")
local ok, city = pcall(function()
  return Players[iTarget]:GetCities():Create(iX, iY)
end)
print("  pcall ok=" .. tostring(ok) .. "  城市对象=" .. tostring(city))

-- 复查
print("")
print("=== 复查 ===")
local cnt, cap, cx, cy = nil, nil, nil, nil
pcall(function() cnt = Players[iTarget]:GetCities():GetCount() end)
pcall(function() cap = Players[iTarget]:GetCities():GetCapitalCity() end)
print("  cities 数 = " .. tostring(cnt))
print("  首都 = " .. tostring(cap))
if cap ~= nil then
  pcall(function() cx, cy = cap:GetX(), cap:GetY() end)
  local nm = nil
  pcall(function() nm = Locale.Lookup(cap:GetName()) end)
  print(string.format("  ✅✅✅ 城邦已建在 (%s,%s)  名字=%s", tostring(cx), tostring(cy), tostring(nm)))
  print("  文明 = " .. tostring(PlayerConfigurations[iTarget]:GetCivilizationTypeName()))
end
print("=== 结束 ===")
