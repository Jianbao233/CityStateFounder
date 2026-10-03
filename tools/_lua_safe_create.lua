-- ★ 严格地块校验后的建城（上次 (18,6) 崩了，(19,5) 成功）
-- 假设：GetCities():Create() 不校验地块，非法地块 → 原生崩溃。
-- 本脚本：只挑【绝对安全】的地块 —— 离所有城市远、无主、纯陆地。
print("=== 严格校验后的建城 ===")

-- ── 1. 收集所有已有城市的位置 ──────────────────────────────────────────
local tCity = {}
for i = 0, 63 do
  local p = nil
  pcall(function() p = Players[i] end)
  if p ~= nil then
    local alive = nil
    pcall(function() alive = p:IsAlive() end)
    if alive == true then
      pcall(function()
        local cities = p:GetCities()
        if cities ~= nil then
          for city in cities() do
            tCity[#tCity+1] = { x = city:GetX(), y = city:GetY(), owner = i }
          end
        end
      end)
    end
  end
end
print("  已有城市数 = " .. #tCity)

-- ── 2. 严格挑地块 ──────────────────────────────────────────────────────
local MIN_DIST = 5           -- ★ 离任何城市至少 5 格（上次崩的 (18,6) 可能太近）
local function dist2(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return dx * dx + dy * dy
end
local iX, iY = -1, -1
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
print(string.format("  地图 %dx%d", w, h))

pcall(function()
  for y = 4, h - 5 do
    for x = 4, w - 5 do
      local plot = Map.GetPlot(x, y)
      if plot ~= nil and plot:IsWater() == false and plot:GetOwner() == -1
         and plot:GetFeatureType() == -1 and plot:GetImprovementType() == -1 then
        -- 邻格陆地 ≥ 4
        local land = 0
        for d = 0, 5 do
          local nb = Map.GetAdjacentPlot(x, y, d)
          if nb ~= nil and nb:IsWater() == false then land = land + 1 end
        end
        if land >= 4 then
          -- ★ 离所有城市 ≥ MIN_DIST
          local ok = true
          for _, c in ipairs(tCity) do
            if dist2(x, y, c.x, c.y) < MIN_DIST * MIN_DIST then ok = false break end
          end
          if ok then
            -- ★ 邻格 3 环内没有别的城市
            iX, iY = x, y
            return
          end
        end
      end
    end
  end
end)
print(string.format("  严格校验后目标格 = (%d,%d)", iX, iY))
if iX < 0 then print("  ❌ 找不到满足条件的格（地图太挤）"); return end

-- ── 3. 目标：激活一个【原版】未激活城邦槽 ─────────────────────────────
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
if iT < 0 then print("  ❌ 没有可激活的原版城邦槽"); return end
print(string.format("  目标: slot %d  %s", iT, sCiv))

-- ── 4. 激活 ────────────────────────────────────────────────────────────
print("")
print("=== 激活 ===")
pcall(function() pm:SetPlayerSlotStatus(iT, 1) end)
pcall(function() pm:InitializePlayer(iT) end)
local alive = nil; pcall(function() alive = Players[iT]:IsAlive() end)
print("  alive = " .. tostring(alive))
if alive ~= true then print("  ❌ 激活失败"); return end

-- ── 5. ★ 建城前最后一道校验：该格是否被引擎认为可建城 ──────────────────
print("")
print("=== 建城前校验 ===")
local plot = Map.GetPlot(iX, iY)
if plot == nil then print("  ❌ plot 为 nil"); return end
local function p2(l, f) local ok, v = pcall(f) return ok and tostring(v) or ("ERR:" .. tostring(v)) end
print("  IsWater      = " .. p2(plot, function() return plot:IsWater() end))
print("  GetOwner     = " .. p2(plot, function() return plot:GetOwner() end))
print("  IsOwned      = " .. p2(plot, function() return plot:IsOwned() end))
print("  GetFeatureType = " .. p2(plot, function() return plot:GetFeatureType() end))
print("  GetTerrainType = " .. p2(plot, function() return plot:GetTerrainType() end))
print("  IsFlatlands  = " .. p2(plot, function() return plot:IsFlatlands() end))
print("  IsHills      = " .. p2(plot, function() return plot:IsHills() end))
print("  IsMountain   = " .. p2(plot, function() return plot:IsMountain() end))
print("  GetContinent = " .. p2(plot, function() return plot:GetContinentType() end))
print("  GetCity      = " .. p2(plot, function() return plot:GetCity() end))
print("  IsCity       = " .. p2(plot, function() return plot:IsCity() end))

-- ── 6. 建城 ────────────────────────────────────────────────────────────
print("")
print("=== ★ GetCities():Create(" .. iX .. "," .. iY .. ") ===")
local ok, city = pcall(function()
  return Players[iT]:GetCities():Create(iX, iY)
end)
print("  ok=" .. tostring(ok) .. "  城市=" .. tostring(city))
if city ~= nil then
  local nm, cx, cy = nil, nil, nil
  pcall(function() nm = Locale.Lookup(city:GetName()) end)
  pcall(function() cx, cy = city:GetX(), city:GetY() end)
  print(string.format("  ✅ 城邦「%s」已建在 (%s,%s)", tostring(nm), tostring(cx), tostring(cy)))
  print(string.format("  → 请手动交互：slot %d %s @ (%s,%s)", iT, sCiv, tostring(cx), tostring(cy)))
end
print("=== 结束 ===")
