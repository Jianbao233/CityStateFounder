-- CSF_CustomCityStates.sql
-- 「能力重复、名字不同」的自定义城邦 —— 由 tools/_gen_custom_cs.py 生成，请勿手改。
--
-- 原理：城邦能力由 LeaderTraits 承载；各城邦名字/领袖不同，
--       但指向【同一个 Trait】→ 能力完全相同、名字各自独立。
-- 数据模型依据见 docs/DLL版_调研设计与计划.md 附录 E。

-- 幂等：全部 INSERT OR IGNORE，重复加载安全

-- ⚠️⚠️ 顺序很重要：Types 必须先登记，否则 Civilizations / Leaders 的外键失败。
--   实测踩到（在数据库副本上逐条跑）：
--       INSERT INTO Civilizations -> FOREIGN KEY constraint failed
--   原因：Civilizations.CivilizationType -> Types.Type（外键）
--   Types.Hash 由触发器 OnTypeInsert 调 Make_Hash 自动算，不用我们给。

INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVILIZATION_CSF_CS_01', 'KIND_CIVILIZATION');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('LEADER_MINOR_CIV_CSF_CS_01', 'KIND_LEADER');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVILIZATION_CSF_CS_02', 'KIND_CIVILIZATION');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('LEADER_MINOR_CIV_CSF_CS_02', 'KIND_LEADER');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVILIZATION_CSF_CS_03', 'KIND_CIVILIZATION');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('LEADER_MINOR_CIV_CSF_CS_03', 'KIND_LEADER');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVILIZATION_CSF_CS_04', 'KIND_CIVILIZATION');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('LEADER_MINOR_CIV_CSF_CS_04', 'KIND_LEADER');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVILIZATION_CSF_CS_05', 'KIND_CIVILIZATION');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('LEADER_MINOR_CIV_CSF_CS_05', 'KIND_LEADER');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVILIZATION_CSF_CS_06', 'KIND_CIVILIZATION');
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('LEADER_MINOR_CIV_CSF_CS_06', 'KIND_LEADER');

-- ── 新亚历山大 / Neo Alexandria（能力：MINOR_CIV_SCIENTIFIC_TRAIT）
INSERT OR IGNORE INTO Civilizations
  (CivilizationType, Name, Description, Adjective,
   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
VALUES ('CIVILIZATION_CSF_CS_01', 'LOC_CSF_CS_01_NAME', 'LOC_CSF_CS_01_DESC',
        'LOC_CSF_CS_01_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', 'ETHNICITY_MEDITERRANEAN');

INSERT OR IGNORE INTO Leaders
  (LeaderType, Name, OperationList, IsBarbarianLeader,
   InheritFrom, SceneLayers, Sex, SameSexPercentage)
VALUES ('LEADER_MINOR_CIV_CSF_CS_01', 'LOC_CSF_CS_01_LEADER_NAME', NULL, 0,
        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);

INSERT OR IGNORE INTO CivilizationLeaders
  (LeaderType, CivilizationType, CapitalName)
VALUES ('LEADER_MINOR_CIV_CSF_CS_01', 'CIVILIZATION_CSF_CS_01', 'LOC_CSF_CS_01_CAPITAL');

-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
VALUES ('LEADER_MINOR_CIV_CSF_CS_01', 'MINOR_CIV_SCIENTIFIC_TRAIT');

-- ── 新孟菲斯 / Neo Memphis（能力：MINOR_CIV_SCIENTIFIC_TRAIT）
INSERT OR IGNORE INTO Civilizations
  (CivilizationType, Name, Description, Adjective,
   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
VALUES ('CIVILIZATION_CSF_CS_02', 'LOC_CSF_CS_02_NAME', 'LOC_CSF_CS_02_DESC',
        'LOC_CSF_CS_02_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', 'ETHNICITY_MEDITERRANEAN');

INSERT OR IGNORE INTO Leaders
  (LeaderType, Name, OperationList, IsBarbarianLeader,
   InheritFrom, SceneLayers, Sex, SameSexPercentage)
VALUES ('LEADER_MINOR_CIV_CSF_CS_02', 'LOC_CSF_CS_02_LEADER_NAME', NULL, 0,
        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);

INSERT OR IGNORE INTO CivilizationLeaders
  (LeaderType, CivilizationType, CapitalName)
VALUES ('LEADER_MINOR_CIV_CSF_CS_02', 'CIVILIZATION_CSF_CS_02', 'LOC_CSF_CS_02_CAPITAL');

-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
VALUES ('LEADER_MINOR_CIV_CSF_CS_02', 'MINOR_CIV_SCIENTIFIC_TRAIT');

-- ── 新乌鲁克 / Neo Uruk（能力：MINOR_CIV_CULTURAL_TRAIT）
INSERT OR IGNORE INTO Civilizations
  (CivilizationType, Name, Description, Adjective,
   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
VALUES ('CIVILIZATION_CSF_CS_03', 'LOC_CSF_CS_03_NAME', 'LOC_CSF_CS_03_DESC',
        'LOC_CSF_CS_03_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', 'ETHNICITY_MID_EAST');

INSERT OR IGNORE INTO Leaders
  (LeaderType, Name, OperationList, IsBarbarianLeader,
   InheritFrom, SceneLayers, Sex, SameSexPercentage)
VALUES ('LEADER_MINOR_CIV_CSF_CS_03', 'LOC_CSF_CS_03_LEADER_NAME', NULL, 0,
        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);

INSERT OR IGNORE INTO CivilizationLeaders
  (LeaderType, CivilizationType, CapitalName)
VALUES ('LEADER_MINOR_CIV_CSF_CS_03', 'CIVILIZATION_CSF_CS_03', 'LOC_CSF_CS_03_CAPITAL');

-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
VALUES ('LEADER_MINOR_CIV_CSF_CS_03', 'MINOR_CIV_CULTURAL_TRAIT');

-- ── 新尼尼微 / Neo Nineveh（能力：MINOR_CIV_CULTURAL_TRAIT）
INSERT OR IGNORE INTO Civilizations
  (CivilizationType, Name, Description, Adjective,
   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
VALUES ('CIVILIZATION_CSF_CS_04', 'LOC_CSF_CS_04_NAME', 'LOC_CSF_CS_04_DESC',
        'LOC_CSF_CS_04_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', 'ETHNICITY_MID_EAST');

INSERT OR IGNORE INTO Leaders
  (LeaderType, Name, OperationList, IsBarbarianLeader,
   InheritFrom, SceneLayers, Sex, SameSexPercentage)
VALUES ('LEADER_MINOR_CIV_CSF_CS_04', 'LOC_CSF_CS_04_LEADER_NAME', NULL, 0,
        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);

INSERT OR IGNORE INTO CivilizationLeaders
  (LeaderType, CivilizationType, CapitalName)
VALUES ('LEADER_MINOR_CIV_CSF_CS_04', 'CIVILIZATION_CSF_CS_04', 'LOC_CSF_CS_04_CAPITAL');

-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
VALUES ('LEADER_MINOR_CIV_CSF_CS_04', 'MINOR_CIV_CULTURAL_TRAIT');

-- ── 新迦太基 / Neo Carthage（能力：MINOR_CIV_TRADE_TRAIT）
INSERT OR IGNORE INTO Civilizations
  (CivilizationType, Name, Description, Adjective,
   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
VALUES ('CIVILIZATION_CSF_CS_05', 'LOC_CSF_CS_05_NAME', 'LOC_CSF_CS_05_DESC',
        'LOC_CSF_CS_05_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', 'ETHNICITY_MEDITERRANEAN');

INSERT OR IGNORE INTO Leaders
  (LeaderType, Name, OperationList, IsBarbarianLeader,
   InheritFrom, SceneLayers, Sex, SameSexPercentage)
VALUES ('LEADER_MINOR_CIV_CSF_CS_05', 'LOC_CSF_CS_05_LEADER_NAME', NULL, 0,
        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);

INSERT OR IGNORE INTO CivilizationLeaders
  (LeaderType, CivilizationType, CapitalName)
VALUES ('LEADER_MINOR_CIV_CSF_CS_05', 'CIVILIZATION_CSF_CS_05', 'LOC_CSF_CS_05_CAPITAL');

-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
VALUES ('LEADER_MINOR_CIV_CSF_CS_05', 'MINOR_CIV_TRADE_TRAIT');

-- ── 新推罗 / Neo Tyre（能力：MINOR_CIV_TRADE_TRAIT）
INSERT OR IGNORE INTO Civilizations
  (CivilizationType, Name, Description, Adjective,
   RandomCityNameDepth, StartingCivilizationLevelType, Ethnicity)
VALUES ('CIVILIZATION_CSF_CS_06', 'LOC_CSF_CS_06_NAME', 'LOC_CSF_CS_06_DESC',
        'LOC_CSF_CS_06_ADJ', 1, 'CIVILIZATION_LEVEL_CITY_STATE', 'ETHNICITY_MID_EAST');

INSERT OR IGNORE INTO Leaders
  (LeaderType, Name, OperationList, IsBarbarianLeader,
   InheritFrom, SceneLayers, Sex, SameSexPercentage)
VALUES ('LEADER_MINOR_CIV_CSF_CS_06', 'LOC_CSF_CS_06_LEADER_NAME', NULL, 0,
        'LEADER_MINOR_CIV_DEFAULT', 0, 'Male', 0);

INSERT OR IGNORE INTO CivilizationLeaders
  (LeaderType, CivilizationType, CapitalName)
VALUES ('LEADER_MINOR_CIV_CSF_CS_06', 'CIVILIZATION_CSF_CS_06', 'LOC_CSF_CS_06_CAPITAL');

-- ★ 能力：与其它挂同一个 Trait 的城邦完全相同
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
VALUES ('LEADER_MINOR_CIV_CSF_CS_06', 'MINOR_CIV_TRADE_TRAIT');

-- ── 允许它们与原版城邦共存（别名语义，见 DuplicateCivilizations）
--    ⚠️ 两张表成对登记；官方 DuplicateCivilizations 为空、DuplicateLeaders 有 10 行
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_01', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_01', 'CIVILIZATION_BRUSSELS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_02', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_02', 'CIVILIZATION_BRUSSELS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_03', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_03', 'CIVILIZATION_BRUSSELS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_04', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_04', 'CIVILIZATION_BRUSSELS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_05', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_05', 'CIVILIZATION_BRUSSELS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_06', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
VALUES ('CIVILIZATION_CSF_CS_06', 'CIVILIZATION_BRUSSELS');
