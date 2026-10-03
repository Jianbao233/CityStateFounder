-- ★ 面板模拟：把城邦面板/旗标会调的东西全调一遍，找 nil（nil = 交互时会崩的点）
print("=== 面板模拟（城邦 slot 15 ANTIOCH）===")
local i = 15

local function chk(l, f)
  local ok, v = pcall(f)
  local s = ok and tostring(v) or ("ERR:" .. tostring(v))
  local flag = ""
  if ok and (v == nil) then flag = "   ← ★★ nil！面板可能崩" end
  print(string.format("  %-42s %s%s", l, s, flag))
end

print("")
print("=== ① 旗标（CityBanner 会调的）===")
chk("UI.GetPlayerColors(15)", function() local a,b = UI.GetPlayerColors(i); return tostring(a).." / "..tostring(b) end)
chk("PlayerConfigurations:GetColor()", function() return PlayerConfigurations[i]:GetColor() end)
chk("UI.GetPlayerColorValues(civ,0)", function()
  return select(1, UI.GetPlayerColorValues(PlayerConfigurations[i]:GetCivilizationTypeName(), 0))
end)

print("")
print("=== ② 城邦面板（CityStates.lua 会调的）===")
chk("GetCivilizationTypeName", function() return PlayerConfigurations[i]:GetCivilizationTypeName() end)
chk("GetLeaderTypeName", function() return PlayerConfigurations[i]:GetLeaderTypeName() end)
chk("GetLeaderName", function() return PlayerConfigurations[i]:GetLeaderName() end)
chk("GetCivilizationLevelTypeName", function() return PlayerConfigurations[i]:GetCivilizationLevelTypeName() end)
chk("GetPlayerName", function() return PlayerConfigurations[i]:GetPlayerName() end)
chk("GetSlotName", function() return PlayerConfigurations[i]:GetSlotName() end)
chk("GetNickName", function() return PlayerConfigurations[i]:GetNickName() end)
chk("Players[i]:IsAlive()", function() return Players[i]:IsAlive() end)
chk("Players[i]:IsMajor()", function() return Players[i]:IsMajor() end)
chk("Players[i]:GetDiplomacy()", function() return Players[i]:GetDiplomacy() end)
chk("Players[i]:GetInfluence()", function() return Players[i]:GetInfluence() end)
chk("Players[i]:GetCities()", function() return Players[i]:GetCities() end)
chk("Players[i]:GetTreasury()", function() return Players[i]:GetTreasury() end)
chk("Players[i]:GetTechs()", function() return Players[i]:GetTechs() end)
chk("Players[i]:GetCulture()", function() return Players[i]:GetCulture() end)
chk("Players[i]:GetReligion()", function() return Players[i]:GetReligion() end)
chk("Players[i]:GetUnits()", function() return Players[i]:GetUnits() end)

print("")
print("=== ③ 城邦专属数据（面板要读的）===")
chk("GameInfo.Civilizations[civ] 的 Level", function()
  local civ = PlayerConfigurations[i]:GetCivilizationTypeName()
  for r in GameInfo.Civilizations() do
    if r.CivilizationType == civ then return r.StartingCivilizationLevelType end
  end
  return nil
end)
chk("CityStates 表里的类别", function()
  local civ = PlayerConfigurations[i]:GetCivilizationTypeName()
  local rows = DB.ConfigurationQuery("SELECT CityStateCategory FROM CityStates WHERE CivilizationType='" .. civ .. "'")
  if type(rows) == "table" and rows[1] ~= nil then return rows[1].CityStateCategory end
  return nil
end)
chk("宗主加成文本（Influence 的）", function()
  local inf = Players[i]:GetInfluence()
  if inf == nil then return nil end
  return type(inf)
end)
chk("DiplomacyStates（面板历史崩溃点）", function()
  local n = 0
  for r in GameInfo.DiplomaticStates() do n = n + 1 end
  return n .. " 个状态"
end)

print("")
print("=== ④ 与【引擎创建】的城邦对比（找一个正常的）===")
local iRef = -1
for j = 0, 63 do
  if j ~= i then
    local p, pc = nil, nil
    pcall(function() p = Players[j] end)
    pcall(function() pc = PlayerConfigurations[j] end)
    if p ~= nil and pc ~= nil then
      local civ, alive = nil, nil
      pcall(function() civ = pc:GetCivilizationTypeName() end)
      pcall(function() alive = p:IsAlive() end)
      if alive == true and civ ~= nil and civ ~= "" then
        local bCS = false
        pcall(function()
          for r in GameInfo.Civilizations() do
            if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
              bCS = true break end
          end
        end)
        if bCS then iRef = j break end
      end
    end
  end
end
if iRef >= 0 then
  print("  参照: slot " .. iRef)
  for _, fn in ipairs({
    { "GetColor", function(k) return PlayerConfigurations[k]:GetColor() end },
    { "GetLeaderName", function(k) return PlayerConfigurations[k]:GetLeaderName() end },
    { "GetSlotStatus", function(k) return PlayerConfigurations[k]:GetSlotStatus() end },
  }) do
    local a, b = nil, nil
    pcall(function() a = fn[2](i) end)
    pcall(function() b = fn[2](iRef) end)
    print(string.format("    %-18s  我们=%s   引擎=%s", fn[1], tostring(a), tostring(b)))
  end
end
print("=== 结束 ===")
