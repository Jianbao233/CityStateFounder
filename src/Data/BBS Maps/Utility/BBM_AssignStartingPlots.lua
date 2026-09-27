------------------------------------------------------------------------------
--	FILE:	BBS_AssignStartingPlot.lua    -- 2.2.0
--	AUTHOR:  Talasta, Keride, Vodairo
--	PURPOSE: Custom Spawn Placement Script
------------------------------------------------------------------------------
--	Copyright (c) 2014 Firaxis Games, Inc. All rights reserved.
------------------------------------------------------------------------------
include("MapEnums");
include("MapUtilities");
include("FeatureGenerator");
include("TerrainGenerator");
include("NaturalWonderGenerator");
include("ResourceGenerator");
include("AssignStartingPlots");
include "BBM_MapUtils";
include "BBM_SpawnBalancing";
include "BBM_CivilizationAssign";

local BBS_VERSION = "2.2.0"

--------------------------------------------------------------------------------
-- constant definition  --------------------------------------------------------
--------------------------------------------------------------------------------
-- Special civilisations types
BBS_LEADER_TYPE_SPECTATOR = "LEADER_SPECTATOR"

--------------------------------------------------------------------------------
--  Init metatable -------------------------------------------------------------
--------------------------------------------------------------------------------
BBM_AssignStartingPlots = {};
local BBM_HexMap = {};
local BBM_Civilisations = {};
local BBM_Teams = {};
BBM_PlayerNumber = 0;
------------------------------------------------------------------------------
function ___Debug(...)
    print(...);
end

------------------------------------------------------------- BBS ----------------------------
function BBM_AssignStartingPlots.Create(args)
    bbs_game_config = {
        BBM_Team_Spawn = MapConfiguration.GetValue("BBM_Team_Spawn"),
        BBS_MAP_SCRIPT = MapConfiguration.GetValue("MAP_SCRIPT"),
        BBS_MAP_SIZE = Map.GetMapSize(),
        BBS_GAME_SYNC_SEED = GameConfiguration.GetValue("GAME_SYNC_RANDOM_SEED"),
        BBS_MULTIPLAYER_GAME = GameConfiguration.IsAnyMultiplayer(),
        BBS_GAME_SEED = MapConfiguration.GetValue("RANDOM_SEED"),
        BBS_BASE_TEMPERATURE = MapConfiguration.GetValue("temperature"),
        BBS_BOOL_TEMPERATURE = GameConfiguration.GetValue("BBStemp"),
        BBS_RAINFALL = MapConfiguration.GetValue("rainfall"),
        BBS_WORLD_AGE = MapConfiguration.GetValue("world_age"),
        BBS_RIDGE = MapConfiguration.GetValue("BBSRidge"),
        BBS_SEA_LEVEL = MapConfiguration.GetValue("sea_level"),
        BBS_STRATEGIC_RESOURCES = MapConfiguration.GetValue("BBSStratRes"),
        BBS_BASE_RESOURCES = MapConfiguration.GetValue("resources"),
        BBS_START = MapConfiguration.GetValue("start"),
        BBM_MIN_ATTEMPTS = MapConfiguration.GetValue("BBMMinAttempts"),
        BBM_MIN_DISTANCE = MapConfiguration.GetValue("BBMMinDistance")
    }

    instance = {
        __InitStartingData      = BBM_AssignStartingPlots.__InitStartingData,
        __FindBias              = BBM_AssignStartingPlots.__FindBias,
        __ComputeBiasScore      = BBM_AssignStartingPlots.__ComputeBiasScore,
        __GetTerrainIndex       = BBM_AssignStartingPlots.__GetTerrainIndex,
        __GetFeatureIndex       = BBM_AssignStartingPlots.__GetFeatureIndex,
        __GetResourceIndex      = BBM_AssignStartingPlots.__GetResourceIndex,
        __PlaceMajorCivs        = BBM_AssignStartingPlots.__PlaceMajorCivs,
        __ResetMajorsSpawns     = BBM_AssignStartingPlots.__ResetMajorsSpawns,
    }
    print("-----------------------")
    print("Starting BBM Placement",  os.date("%c"))
    print("-----------------------")
    -- Get Bias all
    bbs_negative_bias = {}
    bbs_custom_bias = {}
    -- Custom negative bias located in StartBiasNegatives table
    local ret = DB.Query("SELECT * from StartBiasNegatives");
    for key, value in pairs(ret) do
        if value.CivilizationType ~= nil then
            _Debug("StartBiasNegatives", value.CivilizationType, value.TerrainType,  value.FeatureType, value.Tier, value.Extra);
            table.insert(bbs_negative_bias, {
                CivilizationType = value.CivilizationType,
                TerrainType = value.TerrainType,
                FeatureType = value.FeatureType,
                Tier = value.Tier,
                Extra = value.Extra
            });
        end
    end

    -- Custom bias located in StartBiasNegatives table
    local ret = DB.Query("SELECT * from StartBiasCustom");
    for key, value in pairs(ret) do
        if value.CivilizationType ~= nil then
            _Debug("StartBiasCustom", value.CivilizationType, value.CustomPlacement);
            table.insert(bbs_custom_bias, {
                CivilizationType = value.CivilizationType,
                CustomPlacement = value.CustomPlacement
            });
        end
    end

    -- Get Players data
    local civilisationsIDs = PlayerManager.GetAliveMajorIDs();
    local playerIndex = 1;
    for i = 1, PlayerManager.GetAliveMajorsCount() do
        local player = Players[civilisationsIDs[i]];
        local leader = PlayerConfigurations[civilisationsIDs[i]]:GetLeaderTypeName();
        local name = PlayerConfigurations[civilisationsIDs[i]]:GetCivilizationTypeName();
        local team = Players[civilisationsIDs[i]]:GetTeam();
        local newCivilization = CivilizationAssignSpawn.new(player, leader, name, team, playerIndex)
        if leader ~= BBS_LEADER_TYPE_SPECTATOR then
            playerIndex = playerIndex + 1;
            BBM_Teams[team] = BBM_Teams[team] or {}
            _Debug("IsTeamerConfig - Added in team ", team)
            table.insert(BBM_Teams[team], newCivilization)
            BBM_PlayerNumber = BBM_PlayerNumber + 1;
        end
        _Debug("Leader added ", i, player, leader, name, team)
        table.insert(BBM_Civilisations, newCivilization);
    end

    -- Get City States data
    local BBS_Citystates = {}
    local citystatesIDs = PlayerManager.GetAliveMinorIDs();

    for i = 1, PlayerManager.GetAliveMinorsCount() do
        local player = Players[citystatesIDs[i]];
        local leader = PlayerConfigurations[citystatesIDs[i]]:GetLeaderTypeName();
        local name = PlayerConfigurations[citystatesIDs[i]]:GetCivilizationTypeName();
        local newCS = CivilizationAssignSpawn.new(player, leader, name, nil)

        table.insert(BBS_Citystates, newCS);
    end

    -- Adjust min distance in function of player number
    -- Count number of real players in the game
    total_players = 0
    for i = 1, PlayerManager.GetAliveMajorsCount() do
        player = PlayerConfigurations[civilisationsIDs[i]]
        if (player:GetLeaderTypeName() ~= BBS_LEADER_TYPE_SPECTATOR and player:GetHandicapTypeID() ~= 2021024770) then
            total_players = total_players + 1
        end
    end

    GlobalNumberOfRegions = total_players + PlayerManager.GetAliveMinorsCount();

    if MapConfiguration.GetValue("BBM_Team_Spawn") ~= nil then
        Teamers_Config = MapConfiguration.GetValue("BBM_Team_Spawn")
    end

    instance:__InitStartingData()

    if Contains(MapScripts, bbs_game_config.BBS_MAP_SCRIPT) == false then
        print("Map is not supported by BBM ' Firaxis placement will be used");
        Game:SetProperty("BBM_SUPPORTEDMAP", false)
        CallFiraxisPlacement(args);
        return instance;
    else
        Game:SetProperty("BBM_SUPPORTEDMAP", true)
        print("Map is supported by BBM");
    end

    -- Set game properties
    Game:SetProperty("BBM_MAJOR_DISTANCE", BBM_HexMap.minimumDistanceMajorToMajorCivs);

    print("Start Assign Score Centroid",  os.date("%c"))

    local isTeamer = Is1v1OrTeamerConfig();

    -- Define scores for centroids and place 
    local team1Index = 0;
    local team2Index = 0;
    local firstTeamNumber = nil;
    for _, civ in pairs(BBM_Civilisations) do
        -- On RTS East vs West mod, define position by index (spectator excluded) pp
        -- With odd number teams, the additionnal player will be in sim position
        _Debug("BBM_Teams[civ.CivilizationTeam] = ", civ.CivilizationTeam, BBM_Teams[civ.CivilizationTeam])
        if civ.CivilizationLeader ~= BBS_LEADER_TYPE_SPECTATOR then
            local playerTeamIndex;
            if firstTeamNumber == nil then
                firstTeamNumber = civ.CivilizationTeam
            end
            if civ.CivilizationTeam == firstTeamNumber then
                team1Index = team1Index + 1;
                playerTeamIndex = team1Index;
            else
                team2Index = team2Index + 1;
                playerTeamIndex = team2Index;
            end
            local teamSize = #BBM_Teams[civ.CivilizationTeam] or 1    
            
            if BBM_HexMap.TeamerConfig == TeamerConfigEastVsWest
            or BBM_HexMap.TeamerConfig == TeamerConfigSouthVsNorth then
                civ.TeamerSim = playerTeamIndex <= teamSize / 2 + teamSize % 2;
                civ.TeamerWar = playerTeamIndex > teamSize / 2 + teamSize % 2;
            end  
        end
        civ:CalculateTotalScores(BBM_HexMap);
    end

    print("End Assign Score Centroid",  os.date("%c"))

    print("Start Assign spawn order",  os.date("%c"))
    -- Define spawn order 
    -- Comparing first the number of valid tiles, placing first 
    for _, civ in pairs(BBM_Civilisations) do
        _Debug(tostring(civ.CivilizationLeader).." - ScoreTotal = "..tostring(civ.TotalMapScore).." -  Valid tiles = "..tostring(civ.TotalValidTiles))
    end

    table.sort(BBM_Civilisations,
            function(a, b)
                if a.TotalValidTiles == b.TotalValidTiles then
                    if a.TotalMapScore == b.TotalMapScore then
                        return a.RandomPlaceIdOrder < b.RandomPlaceIdOrder;
                    else
                        return a.TotalMapScore < b.TotalMapScore
                    end
                else
                    -- less score = more constraints for bias respect
                    return a.TotalValidTiles < b.TotalValidTiles
                end
            end)

    for _, civ in pairs(BBM_Civilisations) do
        _Debug(tostring(civ.CivilizationLeader).." - ScoreTotal = "..tostring(civ.TotalMapScore).." -  Valid tiles = "..tostring(civ.TotalValidTiles))
    end

    -- Recursive call 
    local BBS_AssignTries = 0;
    local BBS_Success = false;
    local TriesMajorSpawnableLeft = {};
    while BBS_Success == false and BBS_AssignTries < bbs_game_config.BBM_MIN_ATTEMPTS do
        BBS_AssignTries = BBS_AssignTries + 1;
        -- Place all civs and fill BBM_HexMap.tempMajorSpawns
        local placementOK = instance:__PlaceMajorCivs(BBM_Civilisations, BBM_HexMap, BBS_AssignTries);
        -- Determine how many spawnable tiles left
        local countMajorSpawnableLeft = BBM_HexMap:GetNumberMajorSpawnable(true);
        TriesMajorSpawnableLeft[BBS_AssignTries] = countMajorSpawnableLeft;
       
        instance:__ResetMajorsSpawns(BBM_Civilisations, BBM_HexMap);
        if placementOK == false then
            --instance:__ResetMajorsSpawns(BBM_Civilisations, BBM_HexMap);
            BBM_HexMap.tempMajorSpawns[BBS_AssignTries] = {};
            print("Failed try number "..tostring(BBS_AssignTries))
        else
            print("BBS_Success on try "..tostring(BBS_AssignTries),  os.date("%c"))
        end
    end
    local maxMeanScore = 0;
    local globalMinScore = 0;
    local maxMeanScoreIndex = 0
    local globalMajorSpawnableScore = 0;
    for index, c in pairs(BBM_HexMap.tempMajorSpawns) do
        local list = BBM_HexMap.tempMajorSpawns[index]
        local majorSpawnableScore = TriesMajorSpawnableLeft[index]
        local minLocalScore = 9999;
        local maxLocalScore = 0;
        local minDiffScore = 0;
        local meanScore = 0
        if #list > 0 then
            local totalScore = 0
            for _, civscore in pairs(list) do
                totalScore = totalScore + civscore.Score;
                if civscore.Score < minLocalScore then
                    minLocalScore = civscore.Score;
                end
                if civscore.Score > maxLocalScore then
                    maxLocalScore = civscore.Score;
                end
            end

            _Debug("majorSpawnableScore = ", majorSpawnableScore);

            meanScore = totalScore / #list
            if isTeamer and BBM_HexMap:IsTeamerValidContinentPlacement(index) == false then
                print("Malus try score because all team spawns in a single continent")
                meanScore = meanScore - 20;
            end

            minDiffScore = maxLocalScore - minLocalScore
            -- Take the highest minimum score, if equals, highest mean
            if (minLocalScore > globalMinScore) or (meanScore > maxMeanScore and minLocalScore >= globalMinScore) then
                BBS_Success = true;
                --globalMinDiffScore = minDiffScore;
                maxMeanScore = meanScore;
                globalMinScore = minLocalScore;
                globalMajorSpawnableScore = majorSpawnableScore;
                maxMeanScoreIndex = index;
            end
        end
        print("Assign mean score for try "..tostring(index).." = "..meanScore.." with minimum score of "..tostring(minLocalScore).." and maximum of "..tostring(maxLocalScore))
    end

    print("End Assign spawn order",  os.date("%c"))
    print("BBS_AssignTries = "..tostring(BBS_AssignTries).." - BBS_Success = "..tostring(BBS_Success))
    if BBS_Success then
        print("Selected try max score = "..tostring(maxMeanScoreIndex))
        if isTeamer then
            Game:SetProperty("BBS_TEAMERCONTINENTCHECK", BBM_HexMap:IsTeamerValidContinentPlacement(maxMeanScoreIndex))
        end
        for _, c in pairs(BBM_HexMap.tempMajorSpawns[maxMeanScoreIndex]) do
            _Debug("tempMajorSpawns AssignMajorCivSpawn for "..c.Civ.CivilizationLeader.." "..c.Spawn:PrintXY())
            c.Civ:AssignMajorCivSpawn(BBM_HexMap, c.Spawn);
        end
         -- Firaxis methods for attribution of spawns 
        for j, civ in pairs(BBM_Civilisations) do
            if civ.CivilizationLeader ~= BBS_LEADER_TYPE_SPECTATOR then
                civ.Player:SetStartingPlot(civ.StartingHex.Plot)
                table.insert(BBM_HexMap.majorSpawns, civ.StartingHex);
                local bW, nbW = civ.StartingHex:HasSpawnEnoughWalkableTiles()
                _Debug(civ.CivilizationLeader.." spawn = "..tostring(civ.StartingHex:PrintXY()).." - HasWalkableRequirements = "..tostring(bW).." "..tostring(nbW));
            else
                local hex0 = BBM_HexMap:GetHexInMap(j, 0);
                civ.Player:SetStartingPlot(hex0.Plot)
            end
        end
        -- Measure minimum distance
        local closestDist = 9999
        for _, hex in ipairs(BBM_HexMap.majorSpawns) do
            local localClosestDist = hex:DistanceToClosest(BBM_HexMap, BBM_HexMap.majorSpawns)
            if localClosestDist < closestDist then
                closestDist = localClosestDist;
            end
        end
        Game:SetProperty("BBM_ACTUALMINDIST", closestDist)
        _Debug("BBM_ACTUALMINDIST = ", closestDist)
        _Debug("BBM_ACTUALMINDIST GameProperty = ", Game:GetProperty("BBM_ACTUALMINDIST"))
        print("Start BalanceMap",  os.date("%c"))
        BalanceMap(BBM_HexMap);

        print("Start InitSpawnBalancing",  os.date("%c"))
        local allSpawnBalancing = {}
        for _, civ in pairs(BBM_Civilisations) do
            if civ.CivilizationLeader ~= BBS_LEADER_TYPE_SPECTATOR then
                local spawn = InitSpawnBalancing(BBM_HexMap, civ);
                table.insert(allSpawnBalancing, spawn);
            end
        end
        printAllStartYields(BBM_HexMap);
        BalanceAllCivYields(allSpawnBalancing)
        print("End InitSpawnBalancing",  os.date("%c"))
        
        -- randomly place cs in free space
        for i, cs in pairs(BBS_Citystates) do
            local foundSpawn = false
            local validspawnsleft = BBM_HexMap:GetAnyMinorSpawnablesTiles()
            -- ===== CityStateFounder 补丁（本文件唯一的改动）=====
            -- CCB 原版在这里没有边界检查：validspawnsleft 为空数组时，
            -- 第 351 行算出 rng = -1，第 352 行取下标得到 nil，
            -- 第 353 行索引 nil → "attempt to index a nil value" →
            -- "Call to GenerateMap() had errors" → 地图生成失败、进不了游戏。
            --
            -- 补丁分两步（都实测过）：
            --   ① 出生点用完时【不崩】—— 不再索引 nil。
            --   ② 给这些城邦一个【兜底出生点】。
            --      实测教训：只做 ①（跳过）是不够的 —— 没有出生点的玩家会被
            --      引擎删掉（DLL: "Players without start positions will be
            --      removed."），玩家数量一变，开局直接失败、退回主菜单，
            --      前端弹「一个或多个启动脚本出现错误」。
            --      所以必须给它们一个合法格子。这里统一指向【第一个已放置城邦】
            --      的格子 —— 保证是合法陆地格，且不会污染地图（不调用
            --      AssignMinorCivSpawn，不标记周边）。
            --      这些城邦最终会被本模组收走藏起来，起始格在哪无所谓。
            --
            -- 正常情况（数量在地图容量内）行为与原版完全一致。
            if #validspawnsleft == 0 then
                -- 兜底出生点：找一块【还没被任何玩家占用】的陆地格。
                --
                -- 为什么不能"借"已放置城邦的格子：那格子已经属于别的玩家，
                -- 引擎看到的仍然是两个玩家同一个出生点。
                -- 既然 GetAnyMinorSpawnablesTiles() 返回空，说明每块陆地格
                -- 都落在某个城邦/主文明的排他半径内 —— 但"落在排他半径内"
                -- 不等于"已经有主"。IsCivStartingPlot 才是"已经有主"。
                --
                -- 所以这里直接扫地图，取第一块 IsCivStartingPlot == false
                -- 且可通行的格子，并【立刻把它标记成已占用】，保证后续的
                -- 兜底城邦拿到的是不同的格子。
                --
                -- 这些城邦挤在一起无所谓 —— 它们最终会被本模组收走藏起来。
                local fallbackPlot = nil
                local bFound = false
                pcall(function()
                    for y = 0, BBM_HexMap.height - 1 do
                        for x = 0, BBM_HexMap.width - 1 do
                            local h = BBM_HexMap:GetHexInMap(x, y)
                            if h ~= nil and h.IsCivStartingPlot == false
                               and h:IsImpassable() == false then
                                fallbackPlot = h.Plot
                                h.IsCivStartingPlot = true   -- ★ 占住，避免下一个重复
                                bFound = true
                                break
                            end
                        end
                        if bFound then break end
                    end
                end)
                if fallbackPlot ~= nil then
                    cs.Player:SetStartingPlot(fallbackPlot)
                    local sx, sy = -1, -1
                    pcall(function() sx, sy = fallbackPlot:GetX(), fallbackPlot:GetY() end)
                    print("BBM: [CSF patch] no spawn left for CS "..tostring(i)..
                          " ("..tostring(cs.CivilizationName)..
                          ") -> unique fallback plot ("..tostring(sx)..","..tostring(sy)..
                          ") (kept alive)");
                else
                    print("BBM: [CSF patch] no spawn left for CS "..tostring(i)..
                          " ("..tostring(cs.CivilizationName)..
                          ") and no free plot on the whole map - skipping");
                end
                -- 注意：不 break。后面的城邦同样走这条兜底分支，全部保住。
            else
            -- ===== 补丁结束（以下是 CCB 原逻辑，一行未改）=====
            while foundSpawn == false do
                local rng = TerrainBuilder.GetRandomNumber(#validspawnsleft - 1, "Random valid spawns");
                local testedHex = validspawnsleft[rng+1]
                if testedHex.IsCivStartingPlot == false then
                    foundSpawn = true;
                    cs:AssignMinorCivSpawn(BBM_HexMap, testedHex)
                    cs.Player:SetStartingPlot(cs.StartingHex.Plot)
                    _Debug("CS "..tostring(i).." - "..tostring(cs.CivilizationName).." spawn = "..tostring(cs.StartingHex:PrintXY()))
                end
            end
            end
            
        end

        -- =====================================================================
        -- ===== CityStateFounder：额外创建 floor(N/2) 个休眠城邦（T-156）=====
        -- =====================================================================
        -- 用户的设计：
        --   前端滑条保持【官方原值 X】，玩家自己选本局地图上出现多少城邦 N（≤ X）。
        --   地图照常生成 N 个（观感与原版一致）。
        --   我们再【额外】造 floor(N/2) 个城邦 —— 这些全部休眠、供建邦使者建立。
        --   若城邦池不够 floor(N/2)，则取【池子总数 - N】。
        --
        -- 为什么在这里做：
        --   · 位置在 CCB 放完 N 个【之后】→ 不干扰它的放置与平衡逻辑
        --   · 仍在 GenerateMap() 之内 → 早于引擎的玩家初始化与颜色分配，
        --     所以这些城邦是【引擎正式注册的玩家】（有颜色、有外交状态）
        --
        -- 为什么可以重复用"预分配槽里的城邦文明"：
        --   引擎开局就把 48 个城邦文明预注册进槽位 15-53（status=5，未激活）。
        --   本局只激活 N 个。剩下的那些【没有活着的玩家】，
        --   拿它们新建玩家不会出现"两个同名城邦"。
        --
        -- 打标记 CSF_EXTRA_DORMANT = 1：
        --   让 CSF_Gameplay.lua 的休眠逻辑【优先】收走这些城邦 ——
        --   它们的出生点是兜底的（可能在南极角落），留在地图上会很难看。
        do
            local iBase = #BBS_Citystates
            if iBase > 0 then
                -- ① 收集本局【已用】的城邦文明
                local tUsed = {}
                for _, cs in pairs(BBS_Citystates) do
                    if cs.CivilizationName ~= nil then tUsed[cs.CivilizationName] = true end
                end

                -- ② 找池子里【没被本局激活】的城邦文明
                --    地图上下文没有 DB.ConfigurationQuery，走 GameInfo。
                local tCand = {}
                pcall(function()
                    for row in GameInfo.Civilizations() do
                        local sCiv = row.CivilizationType
                        if sCiv ~= nil and not tUsed[sCiv] then
                            local sLeader = "LEADER_MINOR_CIV_" ..
                                string.gsub(sCiv, "^CIVILIZATION_", "")
                            if GameInfo.Leaders[sLeader] ~= nil then
                                tCand[#tCand + 1] = { Civ = sCiv, Leader = sLeader }
                            end
                        end
                    end
                end)

                -- ③ 目标数量 = floor(N/2)，且不超过候选数
                -- ⚠️ 硬限制：空闲玩家槽只有 54-61 共 8 个（0-53 被主文明与预分配城邦占用，
--    62=自由城市、63=蛮族）。所以额外城邦最多 8 个 —— 下面的循环遇到
--    AddPlayer 返回负数会自动停。要突破这个上限，需要去"激活"槽位 15-53 里
--    那些 status=5 的预分配城邦（引擎开局就把 48 个城邦预注册在那里）。
                local iWant = math.floor(iBase / 2)
                if iWant > #tCand then iWant = #tCand end
                print("BBM: [CSF extra] base CS = "..tostring(iBase)..
                      ", pool candidates = "..tostring(#tCand)..
                      ", target extra = "..tostring(iWant))

                local pm = nil
                pcall(function()
                    pm = WorldBuilder and WorldBuilder.PlayerManager
                         and WorldBuilder.PlayerManager()
                end)

                if pm == nil then
                    print("BBM: [CSF extra] WorldBuilder.PlayerManager 不可用，跳过额外创建")
                else
                    -- 空闲槽用尽时，去"叫醒"预分配槽（15-53）里那些还没激活的城邦。
                    --   引擎开局就把 48 个城邦预注册在这些槽位（status 与活着的城邦不同），
                    --   本局只激活 N 个。剩下的只要把槽位状态改成"和活着的城邦一样"，
                    --   引擎的玩家初始化就会把它们当成正式玩家。
                    --
                    -- ⚠️ 不依赖 SlotStatus 枚举的具体数值 —— 运行时从一个【活着的城邦】
                    --    读它的状态值，再写过去。枚举值只在 Lua 侧，DLL 里查不到。
                    local iAliveStatus = nil
                    pcall(function()
                        local tAlive = PlayerManager.GetAliveMinorIDs()
                        if tAlive ~= nil and tAlive[1] ~= nil then
                            iAliveStatus = PlayerConfigurations[tAlive[1]]:GetSlotStatus()
                        end
                    end)
                    print("BBM: [CSF extra] 空闲槽用尽；活着的城邦槽位状态 = "..
                          tostring(iAliveStatus))

                    local tReusable = {}   -- 可复用的预分配槽
                    if iAliveStatus ~= nil then
                        pcall(function()
                            for slot = 0, 63 do
                                -- ⚠️⚠️ 必须【三重】筛选，缺一不可。
                                -- 实测踩到：只排除"存活的城邦"时，主文明（槽 0 拜占庭，
                                -- 状态 3 ≠ 活城邦的 1）也被选进来了，
                                -- SetSlotStatus 对主文明直接失败 → 整个额外创建中止。
                                --
                                -- ① 槽里必须有文明
                                local sCiv = PlayerConfigurations[slot]:GetCivilizationTypeName()
                                if sCiv ~= nil and sCiv ~= "" then
                                    -- ② 必须是【城邦】—— 看领袖名是不是 LEADER_MINOR_CIV_*
                                    local sLeader = ""
                                    pcall(function()
                                        sLeader = PlayerConfigurations[slot]:GetLeaderTypeName() or ""
                                    end)
                                    local bIsMinor = (string.sub(sLeader, 1, 16) == "LEADER_MINOR_CIV")
                                    -- ③ 必须【还没活】
                                    local bAlive = true
                                    pcall(function() bAlive = Players[slot]:IsAlive() end)
                                    -- ④ 状态必须不是"活着的城邦"那个值
                                    local iSt = -1
                                    pcall(function()
                                        iSt = PlayerConfigurations[slot]:GetSlotStatus()
                                    end)
                                    if bIsMinor and (not bAlive) and iSt ~= iAliveStatus then
                                        tReusable[#tReusable + 1] = slot
                                    end
                                end
                            end
                        end)
                    end
                    print("BBM: [CSF extra] 可叫醒的预分配槽 = "..tostring(#tReusable).." 个")
                    if #tReusable > 0 then
                        local sList = ""
                        for q = 1, math.min(8, #tReusable) do
                            sList = sList .. tostring(tReusable[q]) .. " "
                        end
                        print("BBM: [CSF extra] 前几个: "..sList)
                    end

                    local iMade = 0
                    local iReuse = 0
                    for k = 1, iWant do
                        local cand = tCand[k]
                        local iNew = nil

                        -- 先试空闲槽（AddPlayer）
                        local bOK = pcall(function() iNew = pm:AddPlayer(true) end)
                        if bOK and iNew ~= nil and iNew >= 0 then
                            pcall(function()
                                pm:SetPlayerLeader(iNew, cand.Leader, cand.Civ,
                                                   "CIVILIZATION_LEVEL_CITY_STATE")
                            end)
                        else
                            -- 空闲槽没了 → 叫醒一个预分配槽
                            iReuse = iReuse + 1
                            local slot = tReusable[iReuse]
                            if slot == nil then
                                print("BBM: [CSF extra] 预分配槽也用尽了（第 "..
                                      tostring(k).." 个），停止")
                                break
                            end
                            -- 这个槽里【本来就有城邦文明】，所以不需要 SetPlayerLeader，
                            -- 只要把状态改成"和活着的城邦一样"。
                            local bSt = pcall(function()
                                PlayerConfigurations[slot]:SetSlotStatus(iAliveStatus)
                            end)
                            if not bSt then
                                print("BBM: [CSF extra] SetSlotStatus 失败 slot="..
                                      tostring(slot).."，停止")
                                break
                            end
                            iNew = slot
                            pcall(function()
                                cand.Civ = PlayerConfigurations[slot]:GetCivilizationTypeName()
                            end)
                            print("BBM: [CSF extra] 叫醒预分配槽 "..tostring(slot)..
                                  " -> "..tostring(cand.Civ))
                        end

                        if iNew == nil or iNew < 0 then
                            print("BBM: [CSF extra] 第 "..tostring(k).." 个拿不到槽位，停止")
                            break
                        end

                        -- ④ 给一块【像样】的兜底出生点：可通行、且有可通行的邻格，
                        --    避开地图最外两圈（那里常是极地/冰封死地）
                        local fallbackPlot = nil
                        local bFound = false
                        pcall(function()
                            for y = 2, BBM_HexMap.height - 3 do
                                for x = 2, BBM_HexMap.width - 3 do
                                    local h = BBM_HexMap:GetHexInMap(x, y)
                                    if h ~= nil and h.IsCivStartingPlot == false
                                       and h:IsImpassable() == false then
                                        -- 邻格至少要有一个能通行
                                        local bHasExit = false
                                        for d = 0, 5 do
                                            local nb = Map.GetAdjacentPlot(x, y, d)
                                            if nb ~= nil and nb:IsImpassable() == false then
                                                bHasExit = true
                                                break
                                            end
                                        end
                                        if bHasExit then
                                            fallbackPlot = h.Plot
                                            h.IsCivStartingPlot = true
                                            bFound = true
                                            break
                                        end
                                    end
                                end
                                if bFound then break end
                            end
                        end)

                        if fallbackPlot ~= nil then
                            pcall(function()
                                Players[iNew]:SetStartingPlot(fallbackPlot)
                                -- ★ 标记：让 CSF_Gameplay 优先把这类城邦收走藏起来
                                Players[iNew]:SetProperty("CSF_EXTRA_DORMANT", 1)
                            end)
                            local sx, sy = -1, -1
                            pcall(function() sx, sy = fallbackPlot:GetX(), fallbackPlot:GetY() end)
                            iMade = iMade + 1
                            print("BBM: [CSF extra] #"..tostring(k).." slot="..tostring(iNew)..
                                  " "..tostring(cand.Civ)..
                                  " -> plot ("..tostring(sx)..","..tostring(sy)..")")
                        else
                            print("BBM: [CSF extra] #"..tostring(k).." slot="..tostring(iNew)..
                                  " 找不到空闲陆地格，停止")
                            break
                        end
                    end
                    print("BBM: [CSF extra] done: 额外创建 "..tostring(iMade).." 个休眠城邦")
                end
            end
        end
        -- ===== CityStateFounder 额外创建结束 =====

        Game:SetProperty("BBM_RESPAWN", true)
        print("End Assign Centroid",  os.date("%c"))
    else
        print("BBM: To Many Attempts Failed - Go to Firaxis Placement")
        CallFiraxisPlacement(args);
    end   
    
    print("-----------------------")
    print("Ending BBM Placement",  os.date("%c"))
    print("-----------------------")
    return instance
end

BBS_resources_count = {};

-- Check bias in cluster
-- Check closest water tile from center of cluster
-- Exclude distance to player

-- 1: Min distance between civilisations
-- 2: Spawn bias
-- 3: Fresh water settle
function BBM_AssignStartingPlots:__InitStartingData()
    _Debug("Start parsing map",  os.date("%c"))
    -- Datas stored in HexMap object
    local width, height = Map.GetGridSize();
    BBM_HexMap = HexMap.new(width, height, bbs_game_config.BBS_MAP_SCRIPT);

    --BBM_HexMap:PrintHexSpawnableMap();
    BBM_HexMap:PrintHexPeninsuleMap();

    BBM_HexMap:RunKmeans(GlobalNumberOfRegions, 30);
    BBM_HexMap:PrintHexMap();
    for _, c in pairs(BBM_HexMap.centroidsArray) do
        c:ComputeCentroidScore();
    end
    -- TEMP get hexes from a region (same centroid)
    -- TEMP count % of hills in a region
    for index, centroid in ipairs(BBM_HexMap.centroidsArray) do
        if centroid.HexCluster ~= nil and #centroid.HexCluster > 0 then 
            local count = centroid:GetHillsInCluster();
            local hillPercent = (count / #centroid.HexCluster) * 100
            _Debug("Number of hill in centroid "..tostring(index).." = "..tostring(count).." for a total of "..tostring(#centroid.HexCluster).." tiles (="..tostring(hillPercent).."%)")
            local luxCount, bonusCount, strategicsCount = centroid:GetTotalResourcesCountInCluster();
            _Debug("Number of lux resource in centroid "..tostring(index).." = "..tostring(luxCount))
            _Debug("Number of bonus resource in centroid "..tostring(index).." = "..tostring(bonusCount))
            _Debug("Number of strat resource in centroid "..tostring(index).." = "..tostring(strategicsCount))
        end
    end
    -- Count % of hills on the land map
    local countHills, _ = BBM_HexMap:LookForHills();
    local countLandTiles, _ = BBM_HexMap:GetLandHexList();
    _Debug("totalLandPlots = "..tostring(countLandTiles))
    _Debug("totalHillPlots = "..tostring(countHills))
    _Debug("totalCostal = "..tostring(#BBM_HexMap.mapCostal))
    local hillpercent = (countHills / countLandTiles) * 100
    _Debug("Hill% = "..tostring(hillpercent).." %")
    _Debug("Done parsing map",  os.date("%c"))
end

function BBM_AssignStartingPlots:__PlaceMajorCivs(civs, BBM_HexMap, index) 
-- TODO : manage cases when unable to place a civ => rollback and try again
    BBM_HexMap.tempMajorSpawns[index] = {};
    
    for ind, civ in pairs(civs) do
        if civ.CivilizationLeader ~= BBS_LEADER_TYPE_SPECTATOR then
            local placed, spawnHex, score = civ:AssignSpawnByCentroid(BBM_HexMap);
            if placed == false then
                print("Failed to place civ "..tostring(civ.CivilizationLeader))
                return false;
            end
            table.insert(BBM_HexMap.tempMajorSpawns[index], {Civ = civ, Spawn = spawnHex, Score = score});
            if BBM_HexMap.TeamerConfig == TeamerConfigEastVsWest then
                BBM_HexMap.RTSContinentSetup = BBM_HexMap.RTSContinentSetup or {}
                BBM_HexMap.RTSContinentSetup[civ.CivilizationTeam] = spawnHex.IslandId;
                if spawnHex:GetX() > BBM_HexMap.MiddleX then
                    civ.TeamerSide = EastTeam;
                else
                    civ.TeamerSide = WestTeam;
                end
                for team, _ in pairs(BBM_Teams) do
                    for _, teamCiv in pairs(BBM_Teams[team]) do
                        if teamCiv.TeamerSide == "" then
                            if civ.CivilizationTeam == teamCiv.CivilizationTeam then
                                _Debug("Going through same team civ ", teamCiv.CivilizationLeader, teamCiv.CivilizationTeam, civ.TeamerSide);
                                teamCiv.TeamerSide = civ.TeamerSide;
                                teamCiv.TeamerContinentId = spawnHex.IslandId;
                            else
                                _Debug("Other side for opposing team ", teamCiv.CivilizationLeader, teamCiv.CivilizationTeam, civ.TeamerSide);
                                teamCiv.TeamerSide = getRTSOtherSide(civ.TeamerSide);
                            end
                        end
                    end
                end
                
            end
            if BBM_HexMap.TeamerConfig == TeamerConfigSouthVsNorth then
                BBM_HexMap.RTSContinentSetup = BBM_HexMap.RTSContinentSetup or {}
                BBM_HexMap.RTSContinentSetup[civ.CivilizationTeam] = spawnHex.IslandId;
                if spawnHex:GetY() > BBM_HexMap.MiddleY then
                    civ.TeamerSide = NorthTeam;
                else
                    civ.TeamerSide = SouthTeam;
                end
                _Debug("Vanadium temp checkpoint 1 ",BBM_HexMap.TeamerConfig)
                for team, _ in pairs(BBM_Teams) do
                    for _, teamCiv in pairs(BBM_Teams[team]) do
                        if teamCiv.TeamerSide == "" then
                            if civ.CivilizationTeam == teamCiv.CivilizationTeam then
                                _Debug("Going through same team civ ", teamCiv.CivilizationLeader, teamCiv.CivilizationTeam, civ.TeamerSide);
                                teamCiv.TeamerSide = civ.TeamerSide;
                                teamCiv.TeamerContinentId = spawnHex.IslandId;
                            else
                                _Debug("Other side for opposing team ", teamCiv.CivilizationLeader, teamCiv.CivilizationTeam, civ.TeamerSide);
                                teamCiv.TeamerSide = getRTSOtherSide(civ.TeamerSide);
                            end
                        end
                    end
                end
                
            end
            _Debug("Civ ", ind, " in team ", civ.CivilizationTeam, " - Continent ID = ", spawnHex.IdContinent)
        end
    end
    return true;
end

-- teamerSide = EastTeam or WestTeam global var
function getRTSOtherSide(teamerSide)
    if teamerSide == EastTeam then
        return WestTeam;
    elseif teamerSide == WestTeam then
        return EastTeam;
    elseif teamerSide == SouthTeam then
        return NorthTeam;
    elseif teamerSide == NorthTeam then
        return SouthTeam;
    end
end

function BBM_AssignStartingPlots:__ResetMajorsSpawns(civs, BBM_HexMap)
    BBM_HexMap.majorSpawns = {};
    BBM_HexMap:ResetSpawnableHex();
    for _, civ in pairs(civs) do
        if civ.AttributedCentroid ~= nil then
            civ.AttributedCentroid.PlacedCiv = false;
            civ.TeamerSide = "";
        end
        civ.AttributedCentroid = nil;
        civ.StartingHex = {};
    end
end

-- 1v1 or 2 teams 
-- Fixed index is used here in case team number is not the usual 1 and 2
function Is1v1OrTeamerConfig()
    local teamCount = 0
    local team1Size = 0
    local team2Size = 0
    local fixedIndex = 1
    for team, _ in pairs(BBM_Teams) do
        teamCount = teamCount + 1;
        if fixedIndex == 1 then
            team1Size = #BBM_Teams[team]
        elseif fixedIndex == 2 then
            team2Size = #BBM_Teams[team]
        end
        fixedIndex = fixedIndex + 1;
    end
    local isTeamerConfig = teamCount == 2;
    _Debug("IsTeamerConfig : ", teamCount, team1Size, team2Size, isTeamerConfig);
    return isTeamerConfig;
end

-- Call default fixaris placement script
function CallFiraxisPlacement(args)
    Game:SetProperty("BBM_RESPAWN", false)
    local argSPlot = AssignStartingPlots.Create(args)
end