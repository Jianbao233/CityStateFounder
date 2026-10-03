-- 验证新激活的城邦是不是「真城邦」（颜色/外交/面板）
print("=== 验证新激活城邦的原生性 ===")

-- 找出本轮新激活的（status=1 且是城邦文明的）
local tNew = {}
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    local bCS = false
    pcall(function()
      for r in GameInfo.Civilizations() do
        if r.CivilizationType == civ and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
          bCS = true break
        end
      end
    end)
    if bCS and alive then
      tNew[#tNew+1] = {i=i, civ=civ}
    end
  end
end
print("  已激活城邦 " .. #tNew .. " 个")

-- ★ 重点检查「拉文塔」（我们刚激活并建城的那个）
local iCheck = -1
for _, r in ipairs(tNew) do
  if string.find(r.civ, "LA_VENTA") then iCheck = r.i break end
end
if iCheck < 0 and #tNew > 0 then iCheck = tNew[#tNew].i end
print("  检查对象: slot " .. iCheck)

local function show(label, fn)
  local ok, v = pcall(fn)
  print(string.format("  %-34s %s", label, ok and tostring(v) or ("ERR: " .. tostring(v))))
end

print("")
print("=== ① 颜色（AddPlayer 失败时这里会是 nil）===")
show("UI.GetPlayerColors(slot)", function()
  local a, b = UI.GetPlayerColors(iCheck)
  return tostring(a) .. " / " .. tostring(b)
end)

print("")
print("=== ② 外交状态 ===")
show("GetDiplomacy()", function() return Players[iCheck]:GetDiplomacy() end)
show("HasMet(0)", function() return Players[iCheck]:GetDiplomacy():HasMet(0) end)
show("IsAtWarWith(0)", function() return Players[iCheck]:GetDiplomacy():IsAtWarWith(0) end)

print("")
print("=== ③ 城邦面板数据（DiplomaticStates 曾是崩溃点）===")
show("GetCivilizationTypeName", function() return PlayerConfigurations[iCheck]:GetCivilizationTypeName() end)
show("IsMajor", function() return Players[iCheck]:IsMajor() end)
show("IsMinor", function() return Players[iCheck]:IsMinor() end)
show("GetCities():GetCount()", function() return Players[iCheck]:GetCities():GetCount() end)
show("GetCapitalCity()", function() return Players[iCheck]:GetCities():GetCapitalCity() end)
show("Influence 对象", function() return Players[iCheck]:GetInfluence() end)

print("")
print("=== ④ 首都详情 ===")
pcall(function()
  local cap = Players[iCheck]:GetCities():GetCapitalCity()
  if cap ~= nil then
    print("  名字 = " .. tostring(Locale.Lookup(cap:GetName())))
    print("  坐标 = (" .. tostring(cap:GetX()) .. "," .. tostring(cap:GetY()) .. ")")
    print("  人口 = " .. tostring(cap:GetPopulation()))
    print("  所有者 = " .. tostring(cap:GetOwner()))
  end
end)

print("")
print("=== ⑤ 本局城邦总数（对比激活前）===")
local n = 0
for _, r in ipairs(tNew) do n = n + 1 end
print("  城邦玩家数 = " .. n)
