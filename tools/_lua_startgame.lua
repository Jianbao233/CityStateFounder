-- ★ 完整开局：开界面 → 配玩家槽位 → 设城邦数 → Host
-- 依据：MainMenu.lua:182 OnAdvancedSetup / :958 OnSinglePlayer / :1015 创建游戏
print("=== 完整开局流程 ===")

-- ── 1. 打开创建游戏界面 ─────────────────────────────────────────────────
print("")
print("=== 1. OnAdvancedSetup() ===")
local bOpen = pcall(OnAdvancedSetup);
print("  ok=" .. tostring(bOpen));
-- 注意：本脚本要在 MainMenu 状态跑第一步；若已在 AdvancedSetup，OnAdvancedSetup 为 nil 也能继续

-- ── 2. 设城邦数 ─────────────────────────────────────────────────────────
print("")
print("=== 2. 城邦数 = 22 ===")
pcall(function() GameConfiguration.SetValue("CITY_STATE_COUNT", 22) end);
pcall(function() GameConfiguration.SetValue("RULESET", "RULESET_EXPANSION_2") end);
local v = nil; pcall(function() v = GameConfiguration.GetValue("CITY_STATE_COUNT") end);
print("  CITY_STATE_COUNT = " .. tostring(v));

-- ── 3. ★ 配玩家槽位（关键：不配就没法开局）─────────────────────────────
print("")
print("=== 3. 配玩家槽位 ===")
-- 引擎内部 SlotStatus：0=Open 1=AI 2=Closed 3=Human 4=Observer
local CSF_SLOT_HUMAN, CSF_SLOT_AI = 3, 1;

-- 玩家 0 = 人类
local pc0 = PlayerConfigurations[0];
if pc0 == nil then print("  ❌ PlayerConfigurations[0] 为 nil"); return end

-- 选一个文明 + 领袖（挑第一个可用的）
local sCiv, sLeader = nil, nil;
pcall(function()
  for row in GameInfo.Civilizations() do
    if row.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_FULL_CIV" then
      sCiv = row.CivilizationType; break;
    end
  end
end);
pcall(function()
  for row in GameInfo.Leaders() do
    if row.LeaderType ~= nil then sLeader = row.LeaderType; break end
  end
end);
print("  选定 civ=" .. tostring(sCiv) .. "  leader=" .. tostring(sLeader));

if sCiv ~= nil then pcall(function() pc0:SetCivilizationTypeName(sCiv) end) end;
if sLeader ~= nil then pcall(function() pc0:SetLeaderTypeName(sLeader) end) end;
pcall(function() pc0:SetSlotStatus(CSF_SLOT_HUMAN) end);
pcall(function() pc0:SetValue("Handicap", "HANDICAP_PRINCE") end);

local c1, l1, s1 = nil, nil, nil;
pcall(function() c1 = pc0:GetCivilizationTypeName() end);
pcall(function() l1 = pc0:GetLeaderTypeName() end);
pcall(function() s1 = pc0:GetSlotStatus() end);
print(string.format("  复查 slot0: civ=%s leader=%s status=%s",
      tostring(c1), tostring(l1), tostring(s1)));

-- 其余槽位设成 AI（至少要有一个对手）
for i = 1, 5 do
  local pc = PlayerConfigurations[i];
  if pc ~= nil then
    local b = pcall(function() pc:SetSlotStatus(CSF_SLOT_AI) end);
    if i <= 3 then print("  slot " .. i .. " 设为 AI ok=" .. tostring(b)) end
  end
end

-- ── 4. 跳过领袖开场动画 ────────────────────────────────────────────────
print("")
print("=== 4. Automation.SetAutoStartEnabled(true) ===")
pcall(function() Automation.SetAutoStartEnabled(true) end);
print("  已设（自动过 leader 画面，省 36 秒）");

-- ── 5. 广播配置 + 开局 ──────────────────────────────────────────────────
print("")
print("=== 5. 广播 + HostGame ===")
pcall(function() if Network.BroadcastGameConfig ~= nil then Network.BroadcastGameConfig() end end);
local bH = pcall(function() Network.HostGame(ServerType.SERVER_TYPE_NONE) end);
print("  HostGame ok=" .. tostring(bH));
print("=== 完成 ===")
