-- 验证：城邦文明本身是否有颜色定义（只是没绑到槽位）
print("=== 颜色归属验证 ===")
local slot = 36
local civ = nil
pcall(function() civ = PlayerConfigurations[slot]:GetCivilizationTypeName() end)
print("  slot " .. slot .. " 文明 = " .. tostring(civ))

print("")
print("=== ① UI.GetPlayerColorValues(civType, i) —— 按【文明】取色 ===")
if UI ~= nil and UI.GetPlayerColorValues ~= nil then
  for _, c in ipairs({civ, "CIVILIZATION_PERSIA", "CIVILIZATION_GENEVA"}) do
    for i = 0, 2 do
      local ok, back, front = pcall(function() return UI.GetPlayerColorValues(c, i) end)
      print(string.format("    %-26s i=%d  ok=%s  back=%s front=%s",
            tostring(c), i, tostring(ok), tostring(back), tostring(front)))
    end
  end
else
  print("  ⚠️ UI.GetPlayerColorValues 不存在")
end

print("")
print("=== ② 正常城邦（同类型）的颜色，作对照 ===")
for i = 15, 63 do
  if i ~= slot then
    local pc = nil; pcall(function() pc = PlayerConfigurations[i] end)
    if pc ~= nil then
      local c2, a2 = nil, nil
      pcall(function() c2 = pc:GetCivilizationTypeName() end)
      pcall(function() a2 = Players[i]:IsAlive() end)
      if a2 == true and c2 ~= nil and string.find(c2, "CITY") == nil and c2 ~= "" and c2 ~= civ then
        local back = nil
        pcall(function() back = UI.GetPlayerColors(i) end)
        if back ~= nil then
          print(string.format("    slot %2d  %-26s back=%s", i, c2, tostring(back)))
          break
        end
      end
    end
  end
end

print("")
print("=== ③ PlayerConfigurations 上有没有颜色相关 setter ===")
local pc = PlayerConfigurations[slot]
local cnt = 0
pcall(function()
  for k, v in pairs(pc) do
    if string.find(string.lower(tostring(k)), "color") then
      print("    " .. tostring(k) .. " = " .. tostring(v))
      cnt = cnt + 1
    end
  end
end)
if cnt == 0 then print("    （PlayerConfigurations 上没看到 color 字段）") end
