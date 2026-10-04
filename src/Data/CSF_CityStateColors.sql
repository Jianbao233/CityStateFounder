-- ===========================================================================
-- 城邦缔造者 —— PlayerColors（配置库）
-- ★★★ 这是我们城邦【没有颜色】的根因：从来没写过这张表！
-- 照工坊 3591345334 的 Colors.sql：Usage='Minor'，颜色用【官方常量】
--   PrimaryColor   = COLOR_PLAYER_CITY_STATE_PRIMARY
--   SecondaryColor = COLOR_PLAYER_CITY_STATE_<类别>_SECONDARY
-- ===========================================================================

INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)
VALUES ('CIVILIZATION_CSF_CS_01', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_SCIENTIFIC_SECONDARY');
INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)
VALUES ('CIVILIZATION_CSF_CS_02', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_SCIENTIFIC_SECONDARY');
INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)
VALUES ('CIVILIZATION_CSF_CS_03', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_CULTURAL_SECONDARY');
INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)
VALUES ('CIVILIZATION_CSF_CS_04', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_CULTURAL_SECONDARY');
INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)
VALUES ('CIVILIZATION_CSF_CS_05', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_TRADE_SECONDARY');
INSERT OR REPLACE INTO PlayerColors (Type, Usage, PrimaryColor, SecondaryColor)
VALUES ('CIVILIZATION_CSF_CS_06', 'Minor', 'COLOR_PLAYER_CITY_STATE_PRIMARY', 'COLOR_PLAYER_CITY_STATE_TRADE_SECONDARY');
