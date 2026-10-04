print("=== ★★ 组合测试：DLL 激活 + 槽位状态 ===")

-- 找一个预注册城邦槽
local iT, sCiv = -1, nil
for i = 0, 63 do
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[i] end)
  pcall(function() pl = Players[i] end)
  if pc ~= nil and pl ~= nil then
    local civ, alive, st = nil, nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = pl:IsAlive() end)
    pcall(function() st = pc:GetSlotStatus() end)
    if civ ~= nil and civ ~= "" and alive == false and st == 5 then
      local bCS = false
      pcall(function()
        for r in GameInfo.Civilizations() do
          if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then bCS = true break end
        end
      end)
      if bCS then iT, sCiv = i, civ break end
    end
  end
end
print("  目标: slot " .. tostring(iT) .. "  " .. tostring(sCiv))
if iT < 0 then print("  ❌ 找不到"); return end

local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-28s %s", l, ok and tostring(v) or ("ERR"))) end
local pm = nil; pcall(function() pm = WorldBuilder.PlayerManager() end)
print("  PlayerManager = " .. type(pm))

print("")
print("=== ① 起点 ===")
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("SlotStatus", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("HasGamePlayer", function() return C6FW.HasGamePlayer(iT) end)

print("")
print("=== ② 第一步：DLL 激活 ===")
local ok1, r1 = pcall(C6FW.ActivatePlayer, iT)
print("  ok=" .. tostring(ok1) .. "  返回=" .. tostring(r1))
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("SlotStatus", function() return PlayerConfigurations[iT]:GetSlotStatus() end)

print("")
print("=== ③ 第二步：SetPlayerSlotStatus(slot, 1) ===")
if pm ~= nil then
  local ok2, r2 = pcall(function() return pm:SetPlayerSlotStatus(iT, 1) end)
  print("  ok=" .. tostring(ok2) .. "  返回=" .. tostring(r2))
else
  print("  ⚠️ 拿不到 PlayerManager")
end
chk("IsAlive", function() return Players[iT]:IsAlive() end)
chk("SlotStatus", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("GetColor", function() return PlayerConfigurations[iT]:GetColor() end)
chk("GetCivLevel", function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)
chk("GetCities:GetCount", function() return Players[iT]:GetCities():GetCount() end)
chk("GetDiplomacy", function() return Players[iT]:GetDiplomacy() end)
chk("GetInfluence", function() return Players[iT]:GetInfluence() end)
chk("GetTreasury", function() return Players[iT]:GetTreasury() end)
chk("GetTechs", function() return Players[iT]:GetTechs() end)
chk("GetCulture", function() return Players[iT]:GetCulture() end)
print("=== 结束 ===")