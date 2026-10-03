-- ===========================================================================
-- CSF 城邦「带色 + 可交互」端到端验证（round 12 准备）
-- 用法：游戏进对局后，发到 GameCore_Tuner 状态执行
--   & $py tools\_eval_lua.py tools\_lua_e2e_color.lua --state GameCore_Tuner --port 4318
-- ===========================================================================
print("=== CSF 端到端验证：带色城邦 ===")

-- ── 0. 环境自检 ─────────────────────────────────────────────────────────
print("")
print("=== 0. 环境自检 ===")
print("  C6FW                  = " .. type(C6FW))
print("  C6FW.SetPlayerColor   = " .. type(C6FW and C6FW.SetPlayerColor))
print("  C6FW.GetPlayerColor   = " .. type(C6FW and C6FW.GetPlayerColor))
print("  WorldBuilder.PlayerManager = " .. type(WorldBuilder and WorldBuilder.PlayerManager))
if C6FW == nil or C6FW.SetPlayerColor == nil then
  print("  ⚠️ C6FW DLL 未安装/未加载 —— 补色不可用，本验证只能跑到「无颜色」为止")
end

-- ── 1. 先看一个【引擎创建的】城邦作对照（应有颜色）────────────────────
print("")
print("=== 1. 对照：引擎创建的城邦（应有颜色）===")
local iRef, sRefCiv = -1, nil
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if alive == true and civ ~= nil and civ ~= "" then
      local bCS = false
      pcall(function()
        for r in GameInfo.Civilizations() do
          if r.CivilizationType == civ
             and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break
          end
        end
      end)
      if bCS then iRef, sRefCiv = i, civ break end
    end
  end
end
if iRef >= 0 then
  local c1, c2 = nil, nil
  pcall(function() c1 = PlayerConfigurations[iRef]:GetColor() end)
  pcall(function() c2 = UI.GetPlayerColors(iRef) end)
  print(string.format("  slot %2d %-26s GetColor=%s  UI.GetPlayerColors=%s",
        iRef, sRefCiv, tostring(c1), tostring(c2)))
end

-- ── 2. 找一个未激活的城邦槽 ─────────────────────────────────────────────
print("")
print("=== 2. 目标：未激活的城邦槽 ===")
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then print("  ❌ 无 PlayerManager"); return end
local iT, sCiv = -1, nil
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    if civ ~= nil and civ ~= "" and alive == false then iT, sCiv = i, civ break end
  end
end
if iT < 0 then print("  ❌ 没有未激活的城邦槽了"); return end
local st0 = nil; pcall(function() st0 = pm:GetSlotStatus(iT) end)
print(string.format("  slot %2d  %-26s  GetSlotStatus=%s  alive=false", iT, sCiv, tostring(st0)))

-- ── 3. 三步激活 + 补色 ──────────────────────────────────────────────────
print("")
print("=== 3. 激活（三步公式 + 补色）===")
print("  ① SetPlayerSlotStatus(" .. iT .. ", 1)")
pcall(function() pm:SetPlayerSlotStatus(iT, 1) end)
print("  ② InitializePlayer(" .. iT .. ")")
pcall(function() pm:InitializePlayer(iT) end)
local alive = nil; pcall(function() alive = Players[iT]:IsAlive() end)
print("  → alive = " .. tostring(alive))
if alive ~= true then print("  ❌ 激活失败"); return end

-- ②b 补色
print("  ②b 补色")
local iColor = nil
pcall(function() iColor = PlayerConfigurations[iT]:GetColor() end)
print("     设前 GetColor = " .. tostring(iColor))
if (iColor == nil or iColor == 0) and UI ~= nil and UI.GetPlayerColorValues ~= nil then
  local ok, v = pcall(function() return UI.GetPlayerColorValues(sCiv, 0) end)
  if ok and v ~= nil and v ~= 0 then iColor = v end
end
print("     取到颜色值 = " .. tostring(iColor))
if C6FW ~= nil and C6FW.SetPlayerColor ~= nil and iColor ~= nil and iColor ~= 0 then
  local ok, r = pcall(function()
    return C6FW.SetPlayerColor(PlayerConfigurations[iT], iColor)
  end)
  print("     C6FW.SetPlayerColor ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
else
  print("     ⚠️ 跳过（C6FW 不可用或取不到颜色）")
end
local cAfter, uiAfter = nil, nil
pcall(function() cAfter = PlayerConfigurations[iT]:GetColor() end)
pcall(function() uiAfter = UI.GetPlayerColors(iT) end)
print("     设后 GetColor            = " .. tostring(cAfter))
print("     设后 UI.GetPlayerColors   = " .. tostring(uiAfter))

-- ── 4. 建城 ─────────────────────────────────────────────────────────────
print("")
print("=== 4. 建城 ===")
local iX, iY = -1, -1
pcall(function()
  local w, h = Map.GetGridSize()
  for y = 3, h - 4 do
    for x = 3, w - 4 do
      local plot = Map.GetPlot(x, y)
      if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
         and plot:GetFeatureType() == -1 then
        local land = 0
        for d = 0, 5 do
          local nb = Map.GetAdjacentPlot(x, y, d)
          if nb ~= nil and nb:IsWater() == false then land = land + 1 end
        end
        if land >= 4 then iX, iY = x, y; return end
      end
    end
  end
end)
print(string.format("  目标格 (%d,%d)", iX, iY))
if iX < 0 then print("  ❌ 无合适地块"); return end
local okC, pCity = pcall(function() return Players[iT]:GetCities():Create(iX, iY) end)
print("  Create ok=" .. tostring(okC) .. " 城市=" .. tostring(pCity))
if pCity ~= nil then
  local nm = nil; pcall(function() nm = Locale.Lookup(pCity:GetName()) end)
  print(string.format("  ✅ 城邦「%s」已建在 (%d,%d)", tostring(nm), iX, iY))
end

-- ── 5. 交互前置检查（崩溃前的体检）──────────────────────────────────────
print("")
print("=== 5. 交互前置体检（这些若为 nil，交互就会崩）===")
local function chk(label, fn)
  local ok, v = pcall(fn)
  local s = ok and tostring(v) or ("ERR: " .. tostring(v))
  print(string.format("  %-32s %s", label, s))
end
chk("GetDiplomacy()", function() return Players[iT]:GetDiplomacy() end)
chk("GetInfluence()", function() return Players[iT]:GetInfluence() end)
chk("IsMajor", function() return Players[iT]:IsMajor() end)
chk("GetCities():GetCount()", function() return Players[iT]:GetCities():GetCount() end)
chk("GetCities():GetCapitalCity()", function() return Players[iT]:GetCities():GetCapitalCity() end)
chk("UI.GetPlayerColors()", function() return UI.GetPlayerColors(iT) end)
chk("PlayerConfigurations:GetColor()", function() return PlayerConfigurations[iT]:GetColor() end)
chk("PlayerConfigurations:GetLeaderName()", function() return PlayerConfigurations[iT]:GetLeaderName() end)
chk("PlayerConfigurations:GetSlotStatus()", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("PlayerConfigurations:GetCivilizationLevelTypeName()",
    function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)

print("")
print("=== 结束：请手动交互该城邦（点旗标/开面板/派使者），看是否崩溃 ===")
print(string.format("  目标：slot %d  城邦 %s  坐标 (%d,%d)", iT, sCiv, iX, iY))
