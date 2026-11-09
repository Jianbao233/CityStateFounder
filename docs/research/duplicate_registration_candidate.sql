-- REJECTED AS DUPLICATE ENABLEMENT: research negative control only.
-- Native consumers EXPAND EXCLUSION through these aliases; not coexistence permission.
-- Self-pairs are redundant in the inspected exact-match path. Do not load this file.
-- Gameplay schema only; configuration DuplicateCivilizations has another schema.
-- Includes loaded DLC/custom city-states at SQL execution time, not later loads.
-- Preserves existing aliases; does not prove runtime duplicate support.
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
SELECT CivilizationType, CivilizationType
FROM Civilizations
WHERE StartingCivilizationLevelType = 'CIVILIZATION_LEVEL_CITY_STATE';
