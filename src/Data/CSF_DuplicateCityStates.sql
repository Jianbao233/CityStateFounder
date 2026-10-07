-- 自动生成：官方城邦的「自我共存」登记（DuplicateCivilizations）
--
-- 语义：DuplicateCivilizations 表示「这两个文明可以共存」。
-- 用途：让【同一个城邦能被复制多份】—— 不加登记就复制会让引擎崩溃。
-- 实测（2026-10-04）：官方 54 个城邦原本【全都没有登记】，
--   造副本后点下一回合 → 游戏原生崩溃（无 Lua 报错）。
--
-- ⚠️ 只列官方城邦。自制城邦（CIVILIZATION_CSF_CS_*）已下架，
--    若在此引用它们会报 Invalid Reference → 数据库错误 → 进不了对局。

INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_AMSTERDAM', 'CIVILIZATION_AMSTERDAM');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_BRUSSELS', 'CIVILIZATION_BRUSSELS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_BUENOS_AIRES', 'CIVILIZATION_BUENOS_AIRES');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_CARTHAGE', 'CIVILIZATION_CARTHAGE');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_GENEVA', 'CIVILIZATION_GENEVA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_HATTUSA', 'CIVILIZATION_HATTUSA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_HONG_KONG', 'CIVILIZATION_HONG_KONG');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_JAKARTA', 'CIVILIZATION_JAKARTA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_JERUSALEM', 'CIVILIZATION_JERUSALEM');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_KABUL', 'CIVILIZATION_KABUL');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_KANDY', 'CIVILIZATION_KANDY');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_KUMASI', 'CIVILIZATION_KUMASI');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_LA_VENTA', 'CIVILIZATION_LA_VENTA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_LISBON', 'CIVILIZATION_LISBON');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_MOHENJO_DARO', 'CIVILIZATION_MOHENJO_DARO');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_NAN_MADOL', 'CIVILIZATION_NAN_MADOL');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_PRESLAV', 'CIVILIZATION_PRESLAV');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_SEOUL', 'CIVILIZATION_SEOUL');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_STOCKHOLM', 'CIVILIZATION_STOCKHOLM');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_TORONTO', 'CIVILIZATION_TORONTO');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_VALLETTA', 'CIVILIZATION_VALLETTA');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_VILNIUS', 'CIVILIZATION_VILNIUS');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_YEREVAN', 'CIVILIZATION_YEREVAN');
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES ('CIVILIZATION_ZANZIBAR', 'CIVILIZATION_ZANZIBAR');

-- 共 24 个官方城邦
