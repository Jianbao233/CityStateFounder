-- ===========================================================================
-- CityStateFounder / 城邦缔造者
-- 玩法库改动：新增「建邦使节」单位
-- 区段：InGameActions > UpdateDatabase  → 写入【玩法库】
--
-- 设计依据（D-03）：与普通开拓者并存、先无条件解锁（供测试）
-- 关键差异（相对 UNIT_SETTLER）：
--   FoundCity = 0        → 没有「建立城市」按钮
--   PopulationCost 不给  → 不消耗人口（建的是城邦不是自己的城）
--   PrereqTech/Civic 不给 → 无解锁条件
-- 列名与外键已逐项对照 01_GameplaySchema.sql:2833-2917 核实
-- ===========================================================================

-- ① Types：Units.UnitType 有外键指向 Types(Type)，必须先插
INSERT INTO Types (Type, Kind) VALUES ('UNIT_CSF_ENVOY', 'KIND_UNIT');

-- ② Units 本体
--    Cost = 150（按用户要求：标准生产力需求 150）
--    CostProgressionModel = NONE：不做"每造一个涨价"，数量上限改由 Lua 控制
--      （Units 表【没有】MaxPlayerInstances 列——已逐列核实 70 列里没有，
--        所以"数量上限"必须用 Lua 实现，见 Lua/CSF_Gameplay.lua 的 CSF_MAX_ENVOYS）
INSERT INTO Units (
  UnitType, Name, Description,
  BaseSightRange, BaseMoves, Cost,
  Domain, FormationClass,
  FoundCity, CanCapture, ZoneOfControl,
  AdvisorType,
  PurchaseYield, PseudoYieldType
) VALUES (
  'UNIT_CSF_ENVOY',
  'LOC_UNIT_CSF_ENVOY_NAME',
  'LOC_UNIT_CSF_ENVOY_DESCRIPTION',
  3, 2, 150,
  'DOMAIN_LAND', 'FORMATION_CLASS_CIVILIAN',
  0, 0, 0,
  'ADVISOR_GENERIC',
  'YIELD_GOLD', 'PSEUDOYIELD_UNIT_SETTLER'
);

-- ③ TypeTags：与开拓者同为陆地平民
INSERT INTO TypeTags (Type, Tag) VALUES ('UNIT_CSF_ENVOY', 'CLASS_LANDCIVILIAN');

-- ④ UnitAiInfos —— ⚠️ 表名是 UnitAiInfos【不是 UnitAiTypes】！
--    （UnitAiTypes 的列是 AiType/TypeValue/Priority，与单位无关）
--    开拓者是【两行】（Units.xml:151-152，在 <UnitAiInfos> 块内）
INSERT INTO UnitAiInfos (UnitType, AiType) VALUES ('UNIT_CSF_ENVOY', 'UNITAI_SETTLE');
INSERT INTO UnitAiInfos (UnitType, AiType) VALUES ('UNIT_CSF_ENVOY', 'UNITTYPE_CIVILIAN');
