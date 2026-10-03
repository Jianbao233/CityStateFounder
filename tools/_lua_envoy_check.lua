-- 验证「自由建造指定城邦」的完整链路
print("=== [1] 建邦使节单位是否存在 ===")
local u = nil
pcall(function() u = GameInfo.Units["UNIT_CSF_ENVOY"] end)
if u == nil then
  print("  ❌ UNIT_CSF_ENVOY 不在 GameInfo.Units")
else
  print("  ✅ UNIT_CSF_ENVOY 存在")
  print("     Name        = " .. tostring(u.Name))
  print("     Domain      = " .. tostring(u.Domain))
  print("     FormationClass = " .. tostring(u.FormationClass))
  print("     Cost        = " .. tostring(u.Cost))
end
print("  Cost 列是否存在(数据库) = " .. tostring(u ~= nil and u.Cost ~= nil))
print("  PrereqCivic = " .. tostring(u ~= nil and u.PrereqCivic))

print("")
print("=== [2] 本机玩家能不能造它（数据库层检查）===")
local iMe = -1
pcall(function() iMe = Game.GetLocalPlayer() end)
print("  本机玩家 = " .. tostring(iMe))
local pc = nil
pcall(function() pc = PlayerConfigurations[iMe] end)
if pc ~= nil then
  print("  本机文明 = " .. tostring(pcall(function() return pc:GetCivilizationTypeName() end)))
end

print("")
print("=== [3] 本局 6 个自定义城邦的可用性（建邦面板的数据源）===")
local n = 0
for i = 0, 63 do
  local p = nil
  pcall(function() p = Players[i] end)
  if p ~= nil then
    local pc2 = nil
    pcall(function() pc2 = PlayerConfigurations[i] end)
    if pc2 ~= nil then
      local civ = nil
      pcall(function() civ = pc2:GetCivilizationTypeName() end)
      if civ ~= nil and string.find(civ, "CSF_CS_") then
        n = n + 1
        local cities, alive = 0, false
        pcall(function() cities = p:GetCities():GetCount() end)
        pcall(function() alive = p:IsAlive() end)
        print(string.format("  slot %2d  %-24s cities=%d alive=%s", i, civ, cities, tostring(alive)))
      end
    end
  end
end
print("  → 共 " .. n .. " 个")

print("")
print("=== [4] 休眠机制状态（本模组写在玩家身上的标记）===")
local iReserved = 0
for i = 0, 63 do
  local p = nil
  pcall(function() p = Players[i] end)
  if p ~= nil then
    local m = nil
    pcall(function() m = p:GetProperty("CSF_EXTRA_DORMANT") end)
    if m ~= nil and m ~= 0 then iReserved = iReserved + 1 end
  end
end
print("  带 CSF_EXTRA_DORMANT 标记的玩家 = " .. iReserved)

print("")
print("=== [5] CSF_Gameplay 是否在跑（本模组脚本）===")
print("  ExposedMembers.CSF 存在 = " .. tostring(ExposedMembers ~= nil and ExposedMembers.CSF ~= nil))
if ExposedMembers ~= nil and ExposedMembers.CSF ~= nil then
  local k = {}
  for key, _ in pairs(ExposedMembers.CSF) do k[#k+1] = key end
  print("  暴露的接口: " .. table.concat(k, ", "))
end
