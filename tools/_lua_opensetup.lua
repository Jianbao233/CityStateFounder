-- ★ 用 OnAdvancedSetup() 打开「创建游戏」界面（= 单人子菜单第 3 项）
-- 依据：Base\Assets\UI\FrontEnd\MainMenu.lua:182 + 子菜单定义 :1015
print("=== 打开创建游戏界面 ===")
print("  OnAdvancedSetup 存在 = " .. tostring(OnAdvancedSetup ~= nil))
if OnAdvancedSetup == nil then
  print("  ❌ 拿不到 OnAdvancedSetup")
  return
end

local ok, err = pcall(OnAdvancedSetup);
print("  OnAdvancedSetup() ok=" .. tostring(ok) .. " err=" .. tostring(err));

-- 复查：参数对象是否就绪
local tNames = { "RULESET", "MAP_SIZE", "CITY_STATE_COUNT", "GAME_SPEED", "ERA" };
for _, k in ipairs(tNames) do
  local ok2, v = pcall(function() return GameConfiguration.GetValue(k) end);
  print(string.format("    GameConfiguration[%-18s] = %s", k, tostring(ok2 and v or "ERR")));
end

-- 地图参数
for _, k in ipairs({ "MAP_SIZE", "MAP_SCRIPT" }) do
  local ok3, v = pcall(function() return MapConfiguration.GetValue(k) end);
  print(string.format("    MapConfiguration[%-18s] = %s", k, tostring(ok3 and v or "ERR")));
end
print("=== 完成 ===")
