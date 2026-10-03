-- ★★★ 决定性实验：SetPlayerSlotStatus(内部枚举) → InitializePlayer → 查 GetCities
print("=== 实验：设槽位状态 + 初始化 ===")

local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then print("  ❌ 拿不到 PlayerManager"); return end

-- 先看方法是否存在（userdata 不可枚举，只能逐个测）
local names = {"InitializePlayer","UninitializePlayer","IsPlayerInitialized",
               "SetPlayerLeader","SetPlayerSlotStatus","GetSlotStatus",
               "SetPlayerStartingPosition","SetRandomMinorStartingPosition",
               "GetPlayerConfig","GetMaxPlayers","AddPlayer"}
print("=== PlayerManager 方法存在性 ===")
for _, n in ipairs(names) do
  print(string.format("  %-30s %s", n, type(pm[n])))
end

-- 找一个未激活的城邦槽
print("")
print("=== 找未激活的城邦槽 ===")
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
      local st = nil
      pcall(function() st = pm:GetSlotStatus(i) end)
      print(string.format("  slot %2d  civ=%-26s alive=false  GetSlotStatus=%s", i, civ, tostring(st)))
      break
    end
  end
end
if iTarget < 0 then print("  ❌ 没找到"); return end

local function status()
  local a, c, s = nil, nil, nil
  pcall(function() a = Players[iTarget]:IsAlive() end)
  pcall(function() c = Players[iTarget]:GetCities() end)
  pcall(function() s = pm:GetSlotStatus(iTarget) end)
  return tostring(a), tostring(c), tostring(s)
end

local a0, c0, s0 = status()
print("")
print(string.format("  初始: alive=%s  GetCities=%s  GetSlotStatus=%s", a0, c0, s0))

-- ★ ① 设槽位状态为 1（内部枚举 AI）
print("")
print("=== ① SetPlayerSlotStatus(" .. iTarget .. ", 1) ===")
local ok1, e1 = pcall(function() return pm:SetPlayerSlotStatus(iTarget, 1) end)
print("  ok=" .. tostring(ok1) .. " 返回=" .. tostring(e1))
local a1, c1, s1 = status()
print(string.format("  之后: alive=%s  GetCities=%s  GetSlotStatus=%s", a1, c1, s1))

-- ★ ② InitializePlayer
print("")
print("=== ② InitializePlayer(" .. iTarget .. ") ===")
local ok2, e2 = pcall(function() return pm:InitializePlayer(iTarget) end)
print("  ok=" .. tostring(ok2) .. " 返回=" .. tostring(e2))
local a2, c2, s2 = status()
print(string.format("  之后: alive=%s  GetCities=%s  GetSlotStatus=%s", a2, c2, s2))

-- ★ ③ 复查 IsPlayerInitialized
local ini = nil
pcall(function() ini = pm:IsPlayerInitialized(iTarget) end)
print("  IsPlayerInitialized = " .. tostring(ini))

print("")
if c2 ~= "nil" then
  print("  ✅✅✅ 突破！GetCities() 不再是 nil —— 玩家对象建起来了！")
  local cnt = nil
  pcall(function() cnt = Players[iTarget]:GetCities():GetCount() end)
  print("  cities 数 = " .. tostring(cnt))
else
  print("  ❌ GetCities() 仍为 nil")
end
print("=== 结束 ===")
