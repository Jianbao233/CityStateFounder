-- 调试：为什么选不出文明 + 为什么找不到地
print("=== 调试 ===")

-- ① GetGridSize 到底返回什么
local a, b, c = Map.GetGridSize()
print("  Map.GetGridSize() = " .. tostring(a) .. ", " .. tostring(b) .. ", " .. tostring(c))
local w, h = 0, 0
pcall(function() w, h = Map.GetGridSize() end)
print("  w=" .. tostring(w) .. " h=" .. tostring(h))

-- ② GetFoundableCityStates 的结构
local t = nil
local ok, r = pcall(ExposedMembers.CSF.GetFoundableCityStates)
print("  GetFoundableCityStates ok=" .. tostring(ok) .. " 类型=" .. type(r))
t = r
if type(t) == "table" then
    print("  条目数 = " .. #t)
    if #t > 0 then
        print("  第 1 条:")
        for k, v in pairs(t[1]) do print("    " .. tostring(k) .. " = " .. tostring(v)) end
    end
end

-- ③ 场上 alive=true 的文明
local tAlive = {}
local n = 0
for j = 0, 63 do
    local pc, pl = nil, nil
    pcall(function() pc = PlayerConfigurations[j] end)
    pcall(function() pl = Players[j] end)
    if pc ~= nil and pl ~= nil then
        local civ, alive = nil, nil
        pcall(function() civ = pc:GetCivilizationTypeName() end)
        pcall(function() alive = pl:IsAlive() end)
        if civ ~= nil and alive == true then tAlive[civ] = j; n = n + 1 end
    end
end
print("  alive=true 的玩家 " .. n .. " 个")

-- ④ 池子里有多少城邦、其中多少 alive
local nPool, nFree = 0, 0
local tFree = {}
pcall(function()
    for row in GameInfo.Civilizations() do
        if row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
            nPool = nPool + 1
            if tAlive[row.CivilizationType] == nil then
                nFree = nFree + 1
                if #tFree < 5 then tFree[#tFree+1] = row.CivilizationType end
            end
        end
    end
end)
print("  池子城邦 " .. nPool .. " 个，其中【未在场】 " .. nFree .. " 个")
for _, x in ipairs(tFree) do print("    可用: " .. x) end

-- ⑤ 直接测 FindFoundLocation 的内部条件
if #tFree > 0 then
    local sCiv = tFree[1]
    print("")
    print("  用 " .. sCiv .. " 测:")
    local ok2, x2, y2, why2 = pcall(ExposedMembers.CSF.FindFoundLocation, nil)
    print("    FindFoundLocation -> " .. tostring(x2) .. "," .. tostring(y2) .. " 原因=" .. tostring(why2))
    local ok3, b3, w3 = pcall(ExposedMembers.CSF.IsValidLocation, 20, 20, nil)
    print("    IsValidLocation(20,20) -> " .. tostring(b3) .. " 原因=" .. tostring(w3))
    -- 暴力找一个"只有地形"也合法的格子
    local bx, by = -1, -1
    pcall(function()
        for y = 3, h - 4 do
            for x = 3, w - 4 do
                local plot = Map.GetPlot(x, y)
                if plot ~= nil then
                    local bw, bm = true, true
                    pcall(function() bw = plot:IsWater() end)
                    pcall(function() bm = plot:IsMountain() end)
                    if bw == false and bm == false then bx, by = x, y; return end
                end
            end
        end
    end)
    print("    暴力找到的第一个陆地格 = (" .. bx .. "," .. by .. ")")
end
print("=== 结束 ===")
