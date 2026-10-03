-- 探测 MainMenu 状态里可用的入口函数（沙箱不可枚举 _G，只能逐个试）
print("=== MainMenu 入口函数探测 ===")
local tNames = {
  "OnSinglePlayer", "OnCreateGame", "OnLoneGameSingle", "OnLoneGame", "OnLANGame",
  "OnAdvancedSetup", "OnGameSetup", "OnStartGame", "OnPlayGame", "OnNewGame",
  "BuildHeadlessGameSetup", "BuildGameSetup", "ShowGameSetup", "HideGameSetup",
  "GameSetup_RefreshParameters", "RebuildPlayerParameters", "ReleasePlayerParameters",
  "OnMultiplayer", "OnHostGame", "OnLoadGame", "OnResumeGame", "OnOptions",
  "OnContinue", "OnBack", "OnClose", "OnStart",
}
for _, n in ipairs(tNames) do
  local v = nil
  pcall(function() v = _G[n] end)
  if v == nil then
    -- _G 可能不可用，试直接引用
    pcall(function()
      local f = loadstring("return " .. n);
      if f ~= nil then v = f() end
    end)
  end
  print(string.format("  %-32s %s", n, tostring(v ~= nil and type(v) or "nil")))
end

print("")
print("=== 关键全局对象 ===")
for _, n in ipairs({ "GameConfiguration", "MapConfiguration", "PlayerConfigurations",
                     "Network", "UI", "ContextPtr", "g_GameParameters", "GameSetup" }) do
  local v = nil
  pcall(function()
    local f = loadstring("return " .. n);
    if f ~= nil then v = f() end
  end)
  print(string.format("  %-32s %s", n, tostring(v ~= nil and type(v) or "nil")))
end
