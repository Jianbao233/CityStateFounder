-- 复现用户场景：使节站在【自己领土】上
local iMe = 0; pcall(function() iMe = Game.GetLocalPlayer() end)
-- 找一块自己的领土
local tx, ty = -1, -1
pcall(function()
  local w, h = Map.GetGridSize()
  for y = 4, h-5 do
    for x = 4, w-5 do
      local pl = Map.GetPlot(x, y)
      if pl ~= nil then
        local own, w2, m2 = nil, nil, nil
        pcall(function() own = pl:GetOwner() end)
        pcall(function() w2 = pl:IsWater() end)
        pcall(function() m2 = pl:IsMountain() end)
        if own == iMe and w2 == false and m2 == false then tx, ty = x, y; return end
      end
    end
  end
end)
print("  找到自己的领土格 = (" .. tostring(tx) .. "," .. tostring(ty) .. ")")
if tx < 0 then print("  ❌ 没有自己的领土（第 1 回合正常）"); return end
-- 造使节并放上去
local ok = pcall(function() return UnitManager.InitUnit(iMe, "UNIT_CSF_ENVOY", tx, ty) end)
print("  放使节到自己领土 ok=" .. tostring(ok))
-- 走 RequestFound（面板的真实路径），坐标 = 使节所在格
local t = nil; pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
local sCiv = nil
if type(t) == "table" then
  for _, e in ipairs(t) do
    if e.Mode == "slot" or e.Mode == "reuse" then sCiv = e.Civ; break end
  end
end
print("  选中 = " .. tostring(sCiv))
if sCiv ~= nil then
  local ok2, r2 = pcall(ExposedMembers.CSF.RequestFound, sCiv, tx, ty, nil, iMe)
  print("  RequestFound ok=" .. tostring(ok2) .. " 返回=" .. tostring(r2))
end