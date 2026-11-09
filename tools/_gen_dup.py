"""Generate a rejected enablement idea as a research-only negative control.

Default: SQL on stdout. --output PATH: validate, then replace that file atomically.
Only civilizations loaded when the SQL executes are included. This does not prove
runtime duplicate activation works. The native relation EXPANDS EXCLUSION;
self-pairs do not grant coexistence. No modinfo action loads this fixture.
"""
import argparse
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

SQL = """-- REJECTED AS DUPLICATE ENABLEMENT: research negative control only.
-- Native consumers EXPAND EXCLUSION through these aliases; not coexistence permission.
-- Self-pairs are redundant in the inspected exact-match path. Do not load this file.
-- Gameplay schema only; configuration DuplicateCivilizations has another schema.
-- Includes loaded DLC/custom city-states at SQL execution time, not later loads.
-- Preserves existing aliases; does not prove runtime duplicate support.
INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType)
SELECT CivilizationType, CivilizationType
FROM Civilizations
WHERE StartingCivilizationLevelType = 'CIVILIZATION_LEVEL_CITY_STATE';
"""
SCHEMA = """PRAGMA foreign_keys=ON;
CREATE TABLE Civilizations(CivilizationType TEXT PRIMARY KEY, StartingCivilizationLevelType TEXT);
CREATE TABLE DuplicateCivilizations(
 CivilizationType TEXT REFERENCES Civilizations(CivilizationType) ON DELETE CASCADE,
 OtherCivilizationType TEXT REFERENCES Civilizations(CivilizationType) ON DELETE CASCADE,
 PRIMARY KEY(CivilizationType, OtherCivilizationType));
"""


def build_sql():
    return SQL


def validate(sql):
    """Parse/execute on an empty private schema; errors never enter stdout SQL."""
    db = sqlite3.connect(':memory:')
    try:
        db.executescript(SCHEMA)
        db.executescript(sql)
        return []
    except sqlite3.Error as exc:
        return [str(exc)]
    finally:
        db.close()


def write_atomic(path, sql):
    path = Path(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.',
                                         suffix='.tmp', delete=False) as f:
            temporary = Path(f.name)
            f.write(sql.encode('utf-8'))
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    sql = build_sql()
    errors = validate(sql)
    if errors:
        print('SQL validation failed: ' + '; '.join(errors), file=sys.stderr)
        return 2
    try:
        if args.output is None:
            sys.stdout.write(sql)
        else:
            write_atomic(args.output, sql)
    except OSError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
