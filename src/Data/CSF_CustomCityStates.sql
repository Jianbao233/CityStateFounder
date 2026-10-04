-- ===========================================================================
-- 城邦缔造者 —— 6 个自定义城邦（玩法库）
-- ★ 按【官方级写法】生成，参考工坊 3591345334「Modder群友城邦小合集」
-- 由 tools/_gen_custom_cs.py 生成，勿手改
-- ===========================================================================

-- ① Types：文明 / 领袖必须先登记（否则外键失败，整份文件中止）
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

-- ② ★★★ TypeProperties：城邦类别 —— 【面板「类型」读的就是这个】
--    没有它 → 面板显示 unknownType（这是我们之前最大的缺陷）
INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('CIVILIZATION_CSF_CS_01', 'CityStateCategory', 'SCIENTIFIC');
INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('CIVILIZATION_CSF_CS_02', 'CityStateCategory', 'SCIENTIFIC');
INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('CIVILIZATION_CSF_CS_03', 'CityStateCategory', 'CULTURAL');
INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('CIVILIZATION_CSF_CS_04', 'CityStateCategory', 'CULTURAL');
INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('CIVILIZATION_CSF_CS_05', 'CityStateCategory', 'TRADE');
INSERT OR IGNORE INTO TypeProperties (Type, Name, Value) VALUES ('CIVILIZATION_CSF_CS_06', 'CityStateCategory', 'TRADE');

-- ③ Civilizations：等级 = 城邦（Adjective / RandomCityNameDepth 照官方写法）
INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, StartingCivilizationLevelType, RandomCityNameDepth) VALUES ('CIVILIZATION_CSF_CS_01', 'LOC_CSF_CS_01_NAME', 'LOC_CSF_CS_01_DESC', 'LOC_CSF_CS_01_ADJ', 'CIVILIZATION_LEVEL_CITY_STATE', 1);
INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, StartingCivilizationLevelType, RandomCityNameDepth) VALUES ('CIVILIZATION_CSF_CS_02', 'LOC_CSF_CS_02_NAME', 'LOC_CSF_CS_02_DESC', 'LOC_CSF_CS_02_ADJ', 'CIVILIZATION_LEVEL_CITY_STATE', 1);
INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, StartingCivilizationLevelType, RandomCityNameDepth) VALUES ('CIVILIZATION_CSF_CS_03', 'LOC_CSF_CS_03_NAME', 'LOC_CSF_CS_03_DESC', 'LOC_CSF_CS_03_ADJ', 'CIVILIZATION_LEVEL_CITY_STATE', 1);
INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, StartingCivilizationLevelType, RandomCityNameDepth) VALUES ('CIVILIZATION_CSF_CS_04', 'LOC_CSF_CS_04_NAME', 'LOC_CSF_CS_04_DESC', 'LOC_CSF_CS_04_ADJ', 'CIVILIZATION_LEVEL_CITY_STATE', 1);
INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, StartingCivilizationLevelType, RandomCityNameDepth) VALUES ('CIVILIZATION_CSF_CS_05', 'LOC_CSF_CS_05_NAME', 'LOC_CSF_CS_05_DESC', 'LOC_CSF_CS_05_ADJ', 'CIVILIZATION_LEVEL_CITY_STATE', 1);
INSERT OR IGNORE INTO Civilizations (CivilizationType, Name, Description, Adjective, StartingCivilizationLevelType, RandomCityNameDepth) VALUES ('CIVILIZATION_CSF_CS_06', 'LOC_CSF_CS_06_NAME', 'LOC_CSF_CS_06_DESC', 'LOC_CSF_CS_06_ADJ', 'CIVILIZATION_LEVEL_CITY_STATE', 1);

-- ④ CivilizationLeaders：带 CapitalName（官方写法）
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) VALUES ('CIVILIZATION_CSF_CS_01', 'LEADER_MINOR_CIV_CSF_CS_01', 'LOC_CSF_CS_01_CITY');
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) VALUES ('CIVILIZATION_CSF_CS_02', 'LEADER_MINOR_CIV_CSF_CS_02', 'LOC_CSF_CS_02_CITY');
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) VALUES ('CIVILIZATION_CSF_CS_03', 'LEADER_MINOR_CIV_CSF_CS_03', 'LOC_CSF_CS_03_CITY');
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) VALUES ('CIVILIZATION_CSF_CS_04', 'LEADER_MINOR_CIV_CSF_CS_04', 'LOC_CSF_CS_04_CITY');
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) VALUES ('CIVILIZATION_CSF_CS_05', 'LEADER_MINOR_CIV_CSF_CS_05', 'LOC_CSF_CS_05_CITY');
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName) VALUES ('CIVILIZATION_CSF_CS_06', 'LEADER_MINOR_CIV_CSF_CS_06', 'LOC_CSF_CS_06_CITY');

-- ⑤ CityNames：城市名（官方写法，缺了会没名字）
INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('CIVILIZATION_CSF_CS_01', 'LOC_CSF_CS_01_CITY');
INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('CIVILIZATION_CSF_CS_02', 'LOC_CSF_CS_02_CITY');
INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('CIVILIZATION_CSF_CS_03', 'LOC_CSF_CS_03_CITY');
INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('CIVILIZATION_CSF_CS_04', 'LOC_CSF_CS_04_CITY');
INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('CIVILIZATION_CSF_CS_05', 'LOC_CSF_CS_05_CITY');
INSERT OR IGNORE INTO CityNames (CivilizationType, CityName) VALUES ('CIVILIZATION_CSF_CS_06', 'LOC_CSF_CS_06_CITY');

-- ⑥ Leaders：InheritFrom 用【官方对应类别的次要文明领袖】
INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES ('LEADER_MINOR_CIV_CSF_CS_01', 'LOC_CSF_CS_01_LEADER', 'LEADER_MINOR_CIV_SCIENTIFIC');
INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES ('LEADER_MINOR_CIV_CSF_CS_02', 'LOC_CSF_CS_02_LEADER', 'LEADER_MINOR_CIV_SCIENTIFIC');
INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES ('LEADER_MINOR_CIV_CSF_CS_03', 'LOC_CSF_CS_03_LEADER', 'LEADER_MINOR_CIV_CULTURAL');
INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES ('LEADER_MINOR_CIV_CSF_CS_04', 'LOC_CSF_CS_04_LEADER', 'LEADER_MINOR_CIV_CULTURAL');
INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES ('LEADER_MINOR_CIV_CSF_CS_05', 'LOC_CSF_CS_05_LEADER', 'LEADER_MINOR_CIV_TRADE');
INSERT OR IGNORE INTO Leaders (LeaderType, Name, InheritFrom) VALUES ('LEADER_MINOR_CIV_CSF_CS_06', 'LOC_CSF_CS_06_LEADER', 'LEADER_MINOR_CIV_TRADE');

-- ⑦ ★★ LeaderTraits：能力 —— 【2 个城邦一组共用同一个官方 Trait】
--    这就是「能力重复但名字不同」：不同文明/领袖，同一个 Trait
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('LEADER_MINOR_CIV_CSF_CS_01', 'MINOR_CIV_SCIENTIFIC_TRAIT');
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('LEADER_MINOR_CIV_CSF_CS_02', 'MINOR_CIV_SCIENTIFIC_TRAIT');
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('LEADER_MINOR_CIV_CSF_CS_03', 'MINOR_CIV_CULTURAL_TRAIT');
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('LEADER_MINOR_CIV_CSF_CS_04', 'MINOR_CIV_CULTURAL_TRAIT');
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('LEADER_MINOR_CIV_CSF_CS_05', 'MINOR_CIV_TRADE_TRAIT');
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType) VALUES ('LEADER_MINOR_CIV_CSF_CS_06', 'MINOR_CIV_TRADE_TRAIT');
