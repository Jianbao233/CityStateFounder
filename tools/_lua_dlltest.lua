print("=== ★ DLL 激活测试 ===")

-- ① 找一个预注册但 alive=false 的城邦槽
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
if iT < 0 then print("  ❌ 找不到可激活的槽"); return end

-- ② 激活前状态
print("")
print("=== ① 激活前 ===")
local function chk(l, fn) local ok, v = pcall(fn); print(string.format("  %-28s %s", l, ok and tostring(v) or ("ERR:"..tostring(v)))) end
chk("Players[i]:IsAlive()", function() return Players[iT]:IsAlive() end)
chk("GetSlotStatus()", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("HasGamePlayer", function() return C6FW.HasGamePlayer(iT) end)
chk("GetPlayerColor(cfg)", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)

-- ③ ★ 用 DLL 激活
print("")
print("=== ② ★ C6FW.ActivatePlayer(" .. iT .. ") ===")
local ok, r = pcall(C6FW.ActivatePlayer, iT)
print("  调用 ok=" .. tostring(ok) .. "  返回=" .. tostring(r))

-- ④ 激活后状态
print("")
print("=== ③ 激活后 ===")
chk("Players[i]:IsAlive()", function() return Players[iT]:IsAlive() end)
chk("GetSlotStatus()", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("GetPlayerColor(cfg)", function() return C6FW.GetPlayerColor(PlayerConfigurations[iT]) end)
chk("GetCivilizationLevelTypeName", function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)
chk("GetCities():GetCount()", function() return Players[iT]:GetCities():GetCount() end)
chk("GetDiplomacy", function() return Players[iT]:GetDiplomacy() end)
chk("GetInfluence", function() return Players[iT]:GetInfluence() end)
print("=== 结束 ===")