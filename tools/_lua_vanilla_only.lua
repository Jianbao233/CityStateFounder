-- ★ 只用【原版城邦】走完整流程（绕开我们的自定义城邦）
-- 上一次崩溃发生在 CSF_CS_02（我们的自定义城邦）；原版 LA_VENTA 是成功的。
-- 本脚本：只挑原版城邦 → 激活 → 体检 → 建城（分步，便于定位）
print("=== 原版城邦流程验证 ===")

-- ── 1. 挑一个【原版】未激活城邦槽 ───────────────────────────────────────
local iT, sCiv = -1, nil
for i = 15, 63 do
  local p, pc = nil, nil
  pcall(function() p = Players[i] end)
  pcall(function() pc = PlayerConfigurations[i] end)
  if p ~= nil and pc ~= nil then
    local civ, alive = nil, nil
    pcall(function() civ = pc:GetCivilizationTypeName() end)
    pcall(function() alive = p:IsAlive() end)
    -- ★ 排除我们的自定义城邦（CSF_CS_）
    if civ ~= nil and civ ~= "" and alive == false
       and string.find(civ, "CSF_CS_") == nil then
      local bCS = false
      pcall(function()
        for r in GameInfo.Civilizations() do
          if r.CivilizationType == civ
             and r.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            bCS = true break
          end
        end
      end)
      if bCS then iT, sCiv = i, civ break end
    end
  end
end
if iT < 0 then print("  ❌ 没有原版未激活城邦槽"); return end
print(string.format("  目标（原版）: slot %d  %s", iT, sCiv))

-- ── 2. 颜色定义检查（对比我们 vs 原版）────────────────────────────────
print("")
print("=== 颜色定义对比（UI.GetPlayerColorValues）===")
if UI ~= nil and UI.GetPlayerColorValues ~= nil then
  for _, c in ipairs({sCiv, "CIVILIZATION_LA_VENTA", "CIVILIZATION_CSF_CS_02"}) do
    local ok, back, front = pcall(function() return UI.GetPlayerColorValues(c, 0) end)
    print(string.format("  %-26s back=%s front=%s", tostring(c), tostring(back), tostring(front)))
  end
end

-- ── 3. 激活（只做两步，先不建城）─────────────────────────────────────
print("")
print("=== 激活（只两步，先不建城）===")
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
if pm == nil then print("  ❌ 无 PlayerManager"); return end
pcall(function() pm:SetPlayerSlotStatus(iT, 1) end)
pcall(function() pm:InitializePlayer(iT) end)
local alive = nil; pcall(function() alive = Players[iT]:IsAlive() end)
print("  alive = " .. tostring(alive))
if alive ~= true then print("  ❌ 激活失败"); return end

-- ── 4. ★ 交互前置体检（建城【之前】先看有没有 nil）────────────────────
print("")
print("=== 交互前置体检（建城前）===")
local function chk(label, fn)
  local ok, v = pcall(fn)
  print(string.format("  %-34s %s", label, ok and tostring(v) or ("ERR: " .. tostring(v))))
end
chk("GetColor()", function() return PlayerConfigurations[iT]:GetColor() end)
chk("GetCivilizationLevelTypeName()",
    function() return PlayerConfigurations[iT]:GetCivilizationLevelTypeName() end)
chk("GetLeaderName()", function() return PlayerConfigurations[iT]:GetLeaderName() end)
chk("GetSlotStatus()", function() return PlayerConfigurations[iT]:GetSlotStatus() end)
chk("GetDiplomacy()", function() return Players[iT]:GetDiplomacy() end)
chk("GetInfluence()", function() return Players[iT]:GetInfluence() end)
chk("IsMajor", function() return Players[iT]:IsMajor() end)
chk("GetCities()", function() return Players[iT]:GetCities() end)
chk("GetCities():GetCount()", function() return Players[iT]:GetCities():GetCount() end)
chk("GetTreasury()", function() return Players[iT]:GetTreasury() end)
chk("GetTechs()", function() return Players[iT]:GetTechs() end)
chk("GetCulture()", function() return Players[iT]:GetCulture() end)
chk("GetReligion()", function() return Players[iT]:GetReligion() end)

-- ── 5. 建城（原版城邦，独立一步）────────────────────────────────────
print("")
print("=== 建城（原版城邦）===")
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
print("  Create ok=" .. tostring(okC) .. "  城市=" .. tostring(pCity))
if pCity ~= nil then
  local nm, cx, cy = nil, nil, nil
  pcall(function() nm = Locale.Lookup(pCity:GetName()) end)
  pcall(function() cx, cy = pCity:GetX(), pCity:GetY() end)
  print(string.format("  ✅ 城邦「%s」已建在 (%s,%s)", tostring(nm), tostring(cx), tostring(cy)))
  print(string.format("  → 请手动交互：slot %d  %s  @ (%s,%s)", iT, sCiv, tostring(cx), tostring(cy)))
end
print("=== 结束 ===")
