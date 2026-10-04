-- ===========================================================================
-- 城邦缔造者 —— CityStates 表（配置库）
-- ★ 照工坊 3591345334 的 Picker.sql：通用 + XP1 + XP2 三个域各一条
-- 没有这张表 → 城邦面板显示 unknownType、加成文案空白
-- ===========================================================================

INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('CIVILIZATION_CSF_CS_01', 'SCIENTIFIC', 'LOC_CSF_CS_01_NAME', 'ICON_CIVILIZATION_GENEVA', 'LOC_CSF_CS_01_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion1CityStates', 'CIVILIZATION_CSF_CS_01', 'SCIENTIFIC', 'LOC_CSF_CS_01_NAME', 'ICON_CIVILIZATION_GENEVA', 'LOC_CSF_CS_01_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion2CityStates', 'CIVILIZATION_CSF_CS_01', 'SCIENTIFIC', 'LOC_CSF_CS_01_NAME', 'ICON_CIVILIZATION_GENEVA', 'LOC_CSF_CS_01_BONUS');

INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('CIVILIZATION_CSF_CS_02', 'SCIENTIFIC', 'LOC_CSF_CS_02_NAME', 'ICON_CIVILIZATION_HATTUSA', 'LOC_CSF_CS_02_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion1CityStates', 'CIVILIZATION_CSF_CS_02', 'SCIENTIFIC', 'LOC_CSF_CS_02_NAME', 'ICON_CIVILIZATION_HATTUSA', 'LOC_CSF_CS_02_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion2CityStates', 'CIVILIZATION_CSF_CS_02', 'SCIENTIFIC', 'LOC_CSF_CS_02_NAME', 'ICON_CIVILIZATION_HATTUSA', 'LOC_CSF_CS_02_BONUS');

INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('CIVILIZATION_CSF_CS_03', 'CULTURAL', 'LOC_CSF_CS_03_NAME', 'ICON_CIVILIZATION_KUMASI', 'LOC_CSF_CS_03_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion1CityStates', 'CIVILIZATION_CSF_CS_03', 'CULTURAL', 'LOC_CSF_CS_03_NAME', 'ICON_CIVILIZATION_KUMASI', 'LOC_CSF_CS_03_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion2CityStates', 'CIVILIZATION_CSF_CS_03', 'CULTURAL', 'LOC_CSF_CS_03_NAME', 'ICON_CIVILIZATION_KUMASI', 'LOC_CSF_CS_03_BONUS');

INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('CIVILIZATION_CSF_CS_04', 'CULTURAL', 'LOC_CSF_CS_04_NAME', 'ICON_CIVILIZATION_NAN_MADOL', 'LOC_CSF_CS_04_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion1CityStates', 'CIVILIZATION_CSF_CS_04', 'CULTURAL', 'LOC_CSF_CS_04_NAME', 'ICON_CIVILIZATION_NAN_MADOL', 'LOC_CSF_CS_04_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion2CityStates', 'CIVILIZATION_CSF_CS_04', 'CULTURAL', 'LOC_CSF_CS_04_NAME', 'ICON_CIVILIZATION_NAN_MADOL', 'LOC_CSF_CS_04_BONUS');

INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('CIVILIZATION_CSF_CS_05', 'TRADE', 'LOC_CSF_CS_05_NAME', 'ICON_CIVILIZATION_ZANZIBAR', 'LOC_CSF_CS_05_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion1CityStates', 'CIVILIZATION_CSF_CS_05', 'TRADE', 'LOC_CSF_CS_05_NAME', 'ICON_CIVILIZATION_ZANZIBAR', 'LOC_CSF_CS_05_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion2CityStates', 'CIVILIZATION_CSF_CS_05', 'TRADE', 'LOC_CSF_CS_05_NAME', 'ICON_CIVILIZATION_ZANZIBAR', 'LOC_CSF_CS_05_BONUS');

INSERT OR IGNORE INTO CityStates (CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('CIVILIZATION_CSF_CS_06', 'TRADE', 'LOC_CSF_CS_06_NAME', 'ICON_CIVILIZATION_VILNIUS', 'LOC_CSF_CS_06_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion1CityStates', 'CIVILIZATION_CSF_CS_06', 'TRADE', 'LOC_CSF_CS_06_NAME', 'ICON_CIVILIZATION_VILNIUS', 'LOC_CSF_CS_06_BONUS');

INSERT OR IGNORE INTO CityStates (Domain, CivilizationType, CityStateCategory, Name, Icon, Bonus)
VALUES ('Expansion2CityStates', 'CIVILIZATION_CSF_CS_06', 'TRADE', 'LOC_CSF_CS_06_NAME', 'ICON_CIVILIZATION_VILNIUS', 'LOC_CSF_CS_06_BONUS');
