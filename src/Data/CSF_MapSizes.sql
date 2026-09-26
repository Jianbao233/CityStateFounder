-- ===========================================================================
-- CityStateFounder / 城邦缔造者
-- 配置库改动：城邦数量
--
-- ⚠️ 2026-09-23 改为【不修改城邦数量】
--
-- 原因：实测在单机 + CCB Maps（工坊 3556318517，走 BBS_Assign 自定义地图脚本）
--       组合下，地图生成阶段报
--         BBM_AssignStartingPlots.lua:353: attempt to index a nil value
--         in 'BBS_Assign' / 'GenerateMap'
--       —— 城邦出生点分配时没有空位可用（validspawnsleft 为空）。
--       增加城邦数量会直接加剧这个问题。
--
-- 设计上的替代：预留城邦【从本局已有的城邦里挑】，而不是额外新增。
--   本局城邦数维持原版（如 SMALL 14 / STANDARD 18），
--   其中一部分开局被"送下地图"保持休眠，玩家用建邦使节把它们放上地图。
--   这既避免了与地图脚本类 mod 的冲突（本项目 T-22 已知雷区），
--   也更符合"战略布局"的设计意图（早期城邦变少，玩家亲手决定谁上桌）。
--
-- 若将来确认安全、确实需要额外城邦槽位，再把下面的语句放开并实测。
-- ===========================================================================

-- UPDATE MapSizes SET DefaultCityStates = DefaultCityStates + 12;
-- UPDATE MapSizes SET MaxCityStates     = MaxCityStates     + 12;
-- UPDATE MapSizes SET MinCityStates     = MinCityStates     + 12;

-- 保留一个无害的空操作，确保本文件被加载时不会因为"空文件"报错
SELECT 1;
