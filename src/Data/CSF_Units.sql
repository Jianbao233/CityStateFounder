-- ===========================================================================
-- CityStateFounder / 城邦缔造者
-- 玩法库改动：新增「建邦使节」单位
-- 区段：InGameActions > UpdateDatabase  → 写入【玩法库】
--
-- 设计依据（D-03）：与普通开拓者并存、先无条件解锁（供测试）
-- 关键差异（相对 UNIT_SETTLER）：
--   FoundCity = 0        → 没有原版的「建立城市」按钮（我们只给「建立城邦」）
--   PopulationCost 不给  → 不消耗人口（建的是城邦不是自己的城）
--   PrereqTech/Civic 不给 → 无解锁条件
--   【不注册 UNITAI_SETTLE】→ AI 不会生产它（T-140）
--   【图标复用开拓者】    → 见 Data/CSF_Icons.xml（T-141）
-- 列名与外键已逐项对照 01_GameplaySchema.sql:2833-2917 核实
-- ===========================================================================

-- ① Types：Units.UnitType 有外键指向 Types(Type)，必须先插
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('UNIT_CSF_ENVOY', 'KIND_UNIT');

-- ② Units 本体
--    Cost = 150（按用户要求：标准生产力需求 150）
--    CostProgressionModel = NONE：不做"每造一个涨价"，数量上限改由 Lua 控制
--      （Units 表【没有】MaxPlayerInstances 列——已逐列核实 70 列里没有，
--        所以"数量上限"必须用 Lua 实现，见 Lua/CSF_Gameplay.lua 的 CSF_MAX_ENVOYS）
--
--    ⭐ PseudoYieldType【不设】（T-140）：原来设成 PSEUDOYIELD_UNIT_SETTLER，
--       等于告诉 AI「这个单位值一个开拓者」。去掉后 AI 不再按开拓者给它估值。
INSERT OR IGNORE INTO Units (
  UnitType, Name, Description,
  BaseSightRange, BaseMoves, Cost,
  Domain, FormationClass,
  FoundCity, CanCapture, ZoneOfControl,
  AdvisorType,
  PurchaseYield
) VALUES (
  'UNIT_CSF_ENVOY',
  'LOC_UNIT_CSF_ENVOY_NAME',
  'LOC_UNIT_CSF_ENVOY_DESCRIPTION',
  3, 2, 150,
  'DOMAIN_LAND', 'FORMATION_CLASS_CIVILIAN',
  0, 0, 0,
  'ADVISOR_GENERIC',
  'YIELD_GOLD'
);

-- ②b Units_XP2：⚠️⚠️ 【不要自己插！】
--     实测（2026-10-04）：写 INSERT INTO Units_XP2 (UnitType, MajorCivOnly) VALUES (...) 会报
--         [Gameplay] ERROR: UNIQUE constraint failed: Units_XP2.UnitType
--     而且改成 INSERT OR IGNORE **照样报** —— 说明冲突不是我们这条引起的，
--     而是【引擎的触发器】：Units 表上有触发器，插入新单位时会自动往 Units_XP2 补行。
--     我们这条显式 INSERT 纯属多余，而且会让整份 SQL 报错。
--
--     后果非常严重：这个数据库错误会让【整个 mod 加载失败】——
--     Lua.log 里一条 [CSF] 都没有、UNIT_CSF_ENVOY 不存在、
--     并且**开局时引擎直接 early exit**（日志：LoadGameViewState leaving the network
--     session due to an early exit of the game state）。
--
--     如需 MajorCivOnly 之类的 XP2 字段，请用 UPDATE（触发器已经建好行了）：
UPDATE Units_XP2 SET MajorCivOnly = 1 WHERE UnitType = 'UNIT_CSF_ENVOY';

-- ③ TypeTags：与开拓者同为陆地平民
INSERT OR IGNORE INTO TypeTags (Type, Tag) VALUES ('UNIT_CSF_ENVOY', 'CLASS_LANDCIVILIAN');

-- ④ UnitAiInfos —— ⚠️ 表名是 UnitAiInfos【不是 UnitAiTypes】！
--    （UnitAiTypes 的列是 AiType/TypeValue/Priority，与单位无关）
--
--    ⚠️⚠️ 这里【刻意只给 UNITTYPE_CIVILIAN，不给 UNITAI_SETTLE】（T-140）：
--       AI 的平民生产逻辑是靠 `UNITAI_SETTLE` 找开拓者的 —— 原先照抄开拓者
--       注册了这个角色，于是 **AI 也会去造「建邦使节」**（用户反馈的问题）。
--       去掉它之后，AI 没有任何代码路径会生产这个单位。
--       保留 UNITTYPE_CIVILIAN 只是把它正确归类为平民单位（移动 / 被俘规则）。
INSERT OR IGNORE INTO UnitAiInfos (UnitType, AiType) VALUES ('UNIT_CSF_ENVOY', 'UNITTYPE_CIVILIAN');
