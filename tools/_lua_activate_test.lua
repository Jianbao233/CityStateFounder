-- ★ 决定性实验：对【未激活】的城邦槽直接建城，能否让它出现？
print("=== 实验：未激活城邦槽 + GetCities():Create ===")

-- 找一个 IsAlive()==false 的城邦槽
local iTarget, sCiv = -1, nil
for i = 54, 63 do
  local p = nil; pcall(function() p = Players[i] end)
  local pc = nil; pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ = nil; pcall(function() civ = pc:GetCivilizationTypeName() end)
    local alive = nil; pcall(function() alive = p:IsAlive() end)
    if civ ~= nil and civ ~= "" and alive == false then
      iTarget, sCiv = i, civ
      print(string.format("  候选：slot %d  civ=%s  alive=false", i, civ))
      break
    end
  end
end
if iTarget < 0 then
  print("  ❌ 54~63 槽里没有找到未激活的城邦（本局可能都激活了）")
  -- 扩大搜索范围
  for i = 15, 53 do
    local p = nil; pcall(function() p = Players[i] end)
    local pc = nil; pcall(function() pc = PlayerConfigurations[i] end)
    if p ~= nil and pc ~= nil then
      local civ = nil; pcall(function() civ = pc:GetCivilizationTypeName() end)
      local alive = nil; pcall(function() alive = p:IsAlive() end)
      if civ ~= nil and civ ~= "" and alive == false then
        iTarget, sCiv = i, civ
        print(string.format("  候选（15~53）：slot %d  civ=%s", i, civ))
        break
      end
    end
  end
end

if iTarget >= 0 then
  print("")
  print("=== 取一个空闲陆地格作为目标 ===")
  local iX, iY = -1, -1
  pcall(function()
    local w, h = Map.GetGridSize()
    for y = 2, h - 3 do
      for x = 2, w - 3 do
        local plot = Map.GetPlot(x, y)
        if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1 then
          iX, iY = x, y; return
        end
      end
    end
  end)
  print(string.format("  目标格 (%d,%d)", iX, iY))

  if iX >= 0 then
    print("")
    print("=== 关键调用：未激活槽 GetCities():Create ===")
    local ok, err, newCity = pcall(function()
      return Players[iTarget]:GetCities():Create(iX, iY)
    end)
    print("  pcall ok=" .. tostring(ok) .. "  err=" .. tostring(err))
    print("  返回城市对象 = " .. tostring(newCity))
    if newCity ~= nil then
      local cx, cy = -1, -1
      pcall(function() cx, cy = newCity:GetX(), newCity:GetY() end)
      print(string.format("  ✅ 城市建在 (%d,%d)", cx, cy))
    end
    -- 复查
    print("")
    print("=== 复查 ===")
    local alive2, cities2 = nil, nil
    pcall(function() alive2 = Players[iTarget]:IsAlive() end)
    pcall(function() cities2 = Players[iTarget]:GetCities():GetCount() end)
    print(string.format("  slot %d：alive=%s  cities=%s", iTarget, tostring(alive2), tostring(cities2)))
    pcall(function()
      local pc = PlayerConfigurations[iTarget]
      print("  文明=" .. tostring(pc:GetCivilizationTypeName()))
    end)
  end
end
print("=== 实验结束 ===")
