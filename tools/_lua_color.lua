-- 在 InGame（UI）上下文测颜色 —— UI.GetPlayerColors 是 UI 函数
print("=== 颜色检查（UI 上下文）===")
local slot = 36
print("  目标 slot = " .. slot)

print("")
print("=== ① UI 全局是否存在 ===")
print("  UI                    = " .. type(UI))
print("  UI.GetPlayerColors    = " .. type(UI and UI.GetPlayerColors))
print("  UI.GetPlayerColorValues = " .. type(UI and UI.GetPlayerColorValues))

print("")
print("=== ② 目标槽的颜色 ===")
if UI ~= nil and UI.GetPlayerColors ~= nil then
  local ok, a, b = pcall(function() return UI.GetPlayerColors(slot) end)
  print("  GetPlayerColors(" .. slot .. ") ok=" .. tostring(ok) .. "  back=" .. tostring(a) .. "  front=" .. tostring(b))
end

print("")
print("=== ③ 对比：原生城邦与非城邦 ===")
for _, i in ipairs({0, slot}) do
  local pc = nil; pcall(function() pc = PlayerConfigurations[i] end)
  local civ, alive = nil, nil
  pcall(function() civ = pc and pc:GetCivilizationTypeName() end)
  pcall(function() alive = Players[i]:IsAlive() end)
  local ok, a, b = pcall(function() return UI.GetPlayerColors(i) end)
  print(string.format("  slot %2d  alive=%-5s civ=%-26s 颜色 ok=%s  back=%s front=%s",
        i, tostring(alive), tostring(civ), tostring(ok), tostring(a), tostring(b)))
end

print("")
print("=== ④ 枚举所有已激活城邦的颜色（看哪些有、哪些没有）===")
local nColor, nNone = 0, 0
for i = 15, 63 do
  local pc = nil; pcall(function() pc = PlayerConfigurations[i] end)
  if pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = Players[i]:IsAlive() end)
    if alive == true and civ ~= nil and civ ~= "" then
      local a = nil
      pcall(function() a = UI.GetPlayerColors(i) end)
      if a ~= nil then nColor = nColor + 1 else
        nNone = nNone + 1
        print(string.format("  ❌ 无颜色: slot %2d  %s", i, civ))
      end
    end
  end
end
print(string.format("  → 有颜色 %d 个，无颜色 %d 个", nColor, nNone))
