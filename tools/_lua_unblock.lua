-- ===========================================================================
-- 解卡 + 过回合：先设研究/市政，再挂机
--
-- 依据（知识库 knowledge/api/civ6-lua-runtime-patterns.md:133）：
--   "若「选择研究」与「市政」未选，Civ6 会挡住回合推进"
--   （knowledge/api/civ6-citystate-player-api.md:280 同款结论）
--
-- 所以过回合前必须先设：
--   ① 研究：UI.RequestPlayerOperation(RESEARCH) / GameCore 兜底 SetResearchingTech
--   ② 市政：UI.RequestPlayerOperation(PROGRESS_CIVIC) / 兜底 SetProgressingCivic
--   ③ 清掉 ENDTURN_BLOCKING_RESEARCH / CIVIC 通知
-- ===========================================================================
print("=== 解卡 + 过回合 ===")

local function try(f)
    local ok, v = pcall(f)
    if not ok then return "ERR(" .. tostring(v):sub(1,50) .. ")" end
    return tostring(v)
end

local iMe = 0
pcall(function() iMe = Game.GetLocalPlayer() end)
print("  本地玩家 = " .. tostring(iMe))

-- ① 找可研究的科技（第一个可研究的）
local iTech = nil
pcall(function()
    local pTechs = Players[iMe]:GetTechs()
    for row in GameInfo.Technologies() do
        local bCan = nil
        pcall(function() bCan = pTechs:CanResearch(row.Index) end)
        local bHas = nil
        pcall(function() bHas = pTechs:HasTech(row.Index) end)
        if bCan == true and bHas ~= true then iTech = row.Index; return end
    end
end)
print("  可研究科技 = " .. tostring(iTech))

-- ② 找可研的市政
local iCivic = nil
pcall(function()
    local pCul = Players[iMe]:GetCulture()
    for row in GameInfo.Civics() do
        local bHas = nil
        pcall(function() bHas = pCul:HasCivic(row.Index) end)
        if bHas ~= true then iCivic = row.Index; return end
    end
end)
print("  可研市政 = " .. tostring(iCivic))

-- ③ GameCore 兜底设置
if iTech ~= nil then
    local ok = pcall(function() Players[iMe]:GetTechs():SetResearchingTech(iTech) end)
    print("  SetResearchingTech ok=" .. tostring(ok))
    local cur = nil; pcall(function() cur = Players[iMe]:GetTechs():GetResearchingTech() end)
    print("  回读 ResearchingTech = " .. tostring(cur))
end
if iCivic ~= nil then
    local ok = pcall(function() Players[iMe]:GetCulture():SetProgressingCivic(iCivic) end)
    print("  SetProgressingCivic ok=" .. tostring(ok))
    local cur2 = nil; pcall(function() cur2 = Players[iMe]:GetCulture():GetProgressingCivic() end)
    print("  回读 ProgressingCivic = " .. tostring(cur2))
end

-- ④ 挂机
print("")
print("  当前回合 = " .. try(function() return Game.GetCurrentGameTurn() end))
print("  IsActive = " .. try(function() return AutoplayManager.IsActive() end))
pcall(function() AutoplayManager.SetTurns(3) end)
pcall(function() AutoplayManager.SetActive(true) end)
print("  IsActive(后) = " .. try(function() return AutoplayManager.IsActive() end))
print("=== 已启动 ===")
