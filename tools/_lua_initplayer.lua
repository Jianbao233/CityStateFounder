-- ★★★ 决定性实验：用 WorldBuilder.PlayerManager():InitializePlayer 激活未激活的城邦槽
print("=== InitializePlayer 实测 ===")

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then print("  ❌ 拿不到 WorldBuilder.PlayerManager()"); return end
print("  ✅ PlayerManager 拿到")

print("")
print("=== PlayerManager 的方法面 ===")
local keys = {}
pcall(function()
  for k, v in pairs(pm) do keys[#keys+1] = k .. "(" .. type(v) .. ")" end
end)
table.sort(keys)
for _, k in ipairs(keys) do print("    " .. k) end

print("")
print("=== 找一个未激活的城邦槽 ===")
local iTarget, sCiv = -1, nil
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive, init = nil, nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if pm.IsPlayerInitialized ~= nil then pcall(function() init = pm:IsPlayerInitialized(i) end) end
    if civ ~= nil and civ ~= "" and alive == false then
      iTarget, sCiv = i, civ
      print(string.format("  slot %2d  civ=%-28s alive=%s IsPlayerInitialized=%s",
            i, civ, tostring(alive), tostring(init)))
      break
    end
  end
end
if iTarget < 0 then print("  ❌ 没找到未激活的城邦槽"); return end

print("")
print("=== ★ 关键：IsPlayerInitialized 前后对比 ===")
local before = nil
pcall(function() before = pm:IsPlayerInitialized(iTarget) end)
print("  调用前 IsPlayerInitialized = " .. tostring(before))

local ok, err = pcall(function() return pm:InitializePlayer(iTarget) end)
print("  InitializePlayer(" .. iTarget .. ") ok=" .. tostring(ok) .. "  返回=" .. tostring(err))

-- 复查（引擎可能要一帧才生效）
print("")
print("=== 复查（等一拍）===")
for _, d in ipairs({0}) do end
local alive2, cities2, init2 = nil, nil, nil
pcall(function() alive2 = Players[iTarget]:IsAlive() end)
pcall(function() cities2 = Players[iTarget]:GetCities() end)
pcall(function() init2 = pm:IsPlayerInitialized(iTarget) end)
print("  alive      = " .. tostring(alive2))
print("  GetCities  = " .. tostring(cities2))
print("  IsInitialized = " .. tostring(init2))
if cities2 ~= nil then
  print("  ✅✅ GetCities() 不再是 nil —— 玩家对象建起来了！")
  local cnt = nil
  pcall(function() cnt = cities2:GetCount() end)
  print("  cities 数 = " .. tostring(cnt))
else
  print("  ❌ GetCities() 仍为 nil")
end
print("=== 实验结束 ===")
