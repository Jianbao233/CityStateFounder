# -*- coding: utf-8 -*-
"""候选登记 SQL 的离线语义测试（stdlib sqlite3 内存库，外键 ON）。

被测对象：
  · docs/research/duplicate_registration_candidate.sql  —— 候选产物本体
  · tools/_gen_dup.py                                   —— 生成器契约与产物自检

约束：全程只用标准库；数据库是 `:memory:`；唯一会写盘的地方是 `tempfile.TemporaryDirectory()`；
不读游戏日志/缓存，不启动游戏，不连 FireTuner，不写 src/，不写游戏 Mods 部署目录。

本地表结构 DDL 抄自本机 XP2 玩法库（只读打开 Cache\\DebugGameplay.sqlite 取得），
主键与两条外键（ON DELETE CASCADE）必须与引擎侧一致，否则这些断言没有意义。

运行：python tools/test_duplicate_registration.py
"""
from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import os
import sqlite3
import sys
import tempfile
import traceback

# 本测试会 importlib 载入生成器；关掉字节码缓存，避免在 tools/__pycache__ 留下新产物。
sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GEN_PATH = os.path.join(HERE, "_gen_dup.py")
CANDIDATE_PATH = os.path.join(ROOT, "docs", "research", "duplicate_registration_candidate.sql")
# 已注册进 modinfo、会被游戏加载的那份文件：本测试只读它的哈希做「没被动过」哨兵。
SENTINEL_PATH = os.path.join(ROOT, "src", "Data", "CSF_DuplicateCityStates.sql")

CS = "CIVILIZATION_LEVEL_CITY_STATE"
MAJOR = "CIVILIZATION_LEVEL_FULL_CIV"
FREE = "CIVILIZATION_LEVEL_FREE_CITIES"
TRIBE = "CIVILIZATION_LEVEL_TRIBE"

SCHEMA = """
CREATE TABLE Civilizations (
    CivilizationType TEXT NOT NULL PRIMARY KEY,
    StartingCivilizationLevelType TEXT
);
CREATE TABLE DuplicateCivilizations (
    CivilizationType TEXT NOT NULL,
    OtherCivilizationType TEXT NOT NULL,
    PRIMARY KEY (CivilizationType, OtherCivilizationType),
    FOREIGN KEY (CivilizationType) REFERENCES Civilizations(CivilizationType)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (OtherCivilizationType) REFERENCES Civilizations(CivilizationType)
        ON DELETE CASCADE ON UPDATE CASCADE
);
"""

with open(CANDIDATE_PATH, "r", encoding="utf-8") as _fh:
    CANDIDATE_SQL = _fh.read()


# ── 辅助 ────────────────────────────────────────────────────────────────────

def new_db(civs=(), dups=()):
    """建一个内存玩法库：外键 ON + 与引擎一致的 Civilizations / DuplicateCivilizations。"""
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys = ON")
    assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1, "外键未开启，测试无效"
    conn.executescript(SCHEMA)
    conn.executemany(
        "INSERT INTO Civilizations (CivilizationType, StartingCivilizationLevelType) VALUES (?, ?)",
        list(civs))
    conn.executemany(
        "INSERT INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) VALUES (?, ?)",
        list(dups))
    return conn


def split_statements(sql):
    """按引擎习惯切分：丢 `--` 整行注释，按分号切，空段忽略（首错即停由调用方体现）。"""
    body = "\n".join(ln for ln in sql.splitlines() if not ln.strip().startswith("--"))
    return [chunk.strip() for chunk in body.split(";") if chunk.strip()]


def apply_candidate(conn, sql):
    for stmt in split_statements(sql):
        conn.execute(stmt)


def rows_of(conn):
    return set(conn.execute(
        "SELECT CivilizationType, OtherCivilizationType FROM DuplicateCivilizations"))


def civs_of(conn):
    return {r[0] for r in conn.execute("SELECT CivilizationType FROM Civilizations")}


def check_no_fk_violation(conn):
    bad = list(conn.execute("PRAGMA foreign_key_check"))
    assert bad == [], "存在悬空外键引用: %r" % (bad,)


def check_no_dangling(conn):
    known = civs_of(conn)
    for a, b in rows_of(conn):
        assert a in known and b in known, "登记行引用了库里不存在的文明: %r" % ((a, b),)


# ── 测试 ────────────────────────────────────────────────────────────────────

def test_level_filter_covers_dlc_and_mod_city_states():
    """DLC 城邦 / 自制城邦都进集合；主文明、自由城市、部落一律排除。"""
    conn = new_db(civs=[
        ("CIVILIZATION_KANDY", CS),           # 基础规则集城邦
        ("CIVILIZATION_BABYLON", CS),         # DLC 城邦
        ("CIVILIZATION_CSF_CS_ALPHA", CS),    # 本 mod 自制城邦
        ("CIVILIZATION_ROME", MAJOR),
        ("CIVILIZATION_FREE_CITIES", FREE),
        ("CIVILIZATION_TRIBE", TRIBE),
    ])
    apply_candidate(conn, CANDIDATE_SQL)
    got = rows_of(conn)
    assert got == {("CIVILIZATION_KANDY", "CIVILIZATION_KANDY"),
                   ("CIVILIZATION_BABYLON", "CIVILIZATION_BABYLON"),
                   ("CIVILIZATION_CSF_CS_ALPHA", "CIVILIZATION_CSF_CS_ALPHA")}, got
    check_no_fk_violation(conn)
    check_no_dangling(conn)


def test_deleted_civ_not_referenced_and_legacy_style_fails():
    """库里没有的文明（XP2 已删除的城邦）既不该被候选 SQL 引用，也不能被旧硬编码写法带进来。"""
    conn = new_db(civs=[("CIVILIZATION_KANDY", CS)])

    # 旧硬编码写法的失败模式：OR IGNORE 不会吞掉外键违规（实测 sqlite3 3.49.1）。
    legacy = ("INSERT OR IGNORE INTO DuplicateCivilizations (CivilizationType, OtherCivilizationType) "
              "VALUES ('CIVILIZATION_AMSTERDAM', 'CIVILIZATION_AMSTERDAM');")
    try:
        apply_candidate(conn, legacy)
    except sqlite3.IntegrityError as exc:
        assert "FOREIGN KEY" in str(exc).upper(), str(exc)
    else:
        raise AssertionError("引用已删除文明的硬编码行本应触发外键错误，却没有报错")

    # 候选 SQL 里不含任何具体文明名，因此不可能生成这种死行。
    # 注意：注释里会提到旧写法的 VALUES（说明历史），所以只检查可执行部分。
    assert "CIVILIZATION_AMSTERDAM" not in CANDIDATE_SQL
    executable = "\n".join(split_statements(CANDIDATE_SQL)).upper()
    assert "VALUES" not in executable, executable

    apply_candidate(conn, CANDIDATE_SQL)
    assert rows_of(conn) == {("CIVILIZATION_KANDY", "CIVILIZATION_KANDY")}
    check_no_dangling(conn)


def test_empty_pool_is_noop():
    """没有城邦（或彻底空库）时静默不产生任何行，也不报错。"""
    conn = new_db(civs=[("CIVILIZATION_ROME", MAJOR)])
    apply_candidate(conn, CANDIDATE_SQL)
    assert rows_of(conn) == set()

    empty = new_db()
    apply_candidate(empty, CANDIDATE_SQL)
    assert rows_of(empty) == set()


def test_preserves_existing_aliases_and_is_idempotent():
    """既有跨文明别名原样保留；自配对幂等；文明被删时登记随之级联消失。"""
    conn = new_db(
        civs=[("CIVILIZATION_KANDY", CS), ("CIVILIZATION_BABYLON", CS), ("CIVILIZATION_ROME", MAJOR)],
        dups=[("CIVILIZATION_KANDY", "CIVILIZATION_ROME"),      # 既有跨文明别名
              ("CIVILIZATION_KANDY", "CIVILIZATION_KANDY")])    # 既有自配对

    apply_candidate(conn, CANDIDATE_SQL)
    first = rows_of(conn)
    assert ("CIVILIZATION_KANDY", "CIVILIZATION_ROME") in first, "跨文明别名被破坏"
    assert ("CIVILIZATION_BABYLON", "CIVILIZATION_BABYLON") in first
    assert len(first) == 3, first

    apply_candidate(conn, CANDIDATE_SQL)          # 重复执行
    assert rows_of(conn) == first, "重复执行产生了新行（不幂等）"

    conn.execute("DELETE FROM Civilizations WHERE CivilizationType = 'CIVILIZATION_BABYLON'")
    after = rows_of(conn)
    assert ("CIVILIZATION_BABYLON", "CIVILIZATION_BABYLON") not in after, "已删除文明仍留有登记行"
    assert ("CIVILIZATION_KANDY", "CIVILIZATION_KANDY") in after
    check_no_fk_violation(conn)


def test_generator_contract_default_stdout_and_atomic_output():
    """生成器：默认只 stdout、产物与文件一致、自检拒绝坏产物、--output 原子且失败不留半成品。"""
    spec = importlib.util.spec_from_file_location("csf_gen_dup", GEN_PATH)
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)

    sql = gen.build_sql()
    assert gen.validate(sql) == [], gen.validate(sql)
    assert sql == CANDIDATE_SQL, "候选文件与生成器输出不一致（产物被手改过？）"

    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = gen.main([])
    assert rc == 0, err.getvalue()
    assert out.getvalue() == sql, "默认模式必须原样打印 SQL 到 stdout"
    assert err.getvalue() == "", "默认模式不该往 stderr 写东西"

    tampered = ("INSERT OR IGNORE INTO DuplicateCivilizations "
                "(CivilizationType, OtherCivilizationType) "
                "VALUES ('CIVILIZATION_KANDY', 'CIVILIZATION_KANDY');")
    assert tampered != sql and gen.validate(tampered), "硬编码 VALUES 写法必须被自检拒绝"
    assert gen.validate(sql.replace("INSERT OR IGNORE", "Traceback (most recent call last):\nINSERT OR IGNORE")), \
        "混入 Python 报错文本必须被自检拒绝"

    with tempfile.TemporaryDirectory() as tmp:
        target = os.path.join(tmp, "candidate.sql")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            assert gen.main(["--output", target]) == 0
        with open(target, "r", encoding="utf-8", newline="") as fh:
            assert fh.read() == sql
        assert os.listdir(tmp) == ["candidate.sql"], "残留临时文件: %r" % (os.listdir(tmp),)

        missing = os.path.join(tmp, "no_such_dir", "candidate.sql")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            assert gen.main(["--output", missing]) != 0, "目录不存在时必须失败"
        assert not os.path.exists(missing)
        assert os.listdir(tmp) == ["candidate.sql"]

        # A failure after writing the temporary file must preserve the old target.
        from unittest import mock
        with open(target, "w", encoding="utf-8") as fh:
            fh.write("old candidate")
        with mock.patch.object(gen.os, "replace", side_effect=OSError("replace failed")):
            with contextlib.redirect_stderr(io.StringIO()):
                assert gen.main(["--output", target]) != 0
        with open(target, encoding="utf-8") as fh:
            assert fh.read() == "old candidate"
        assert os.listdir(tmp) == ["candidate.sql"]


TESTS = (
    test_level_filter_covers_dlc_and_mod_city_states,
    test_deleted_civ_not_referenced_and_legacy_style_fails,
    test_empty_pool_is_noop,
    test_preserves_existing_aliases_and_is_idempotent,
    test_generator_contract_default_stdout_and_atomic_output,
)


def sha256_of(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def leftover_tmp_files():
    found = []
    for d in (HERE, os.path.dirname(CANDIDATE_PATH)):
        for name in os.listdir(d):
            if name.startswith(".csf_dup_") or name.endswith(".tmp"):
                found.append(os.path.join(d, name))
    return found


def main():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass

    sentinel_before = sha256_of(SENTINEL_PATH)
    failures = []
    print("候选 SQL: %s" % CANDIDATE_PATH)
    print("已注册文件(哨兵，只读哈希): %s" % SENTINEL_PATH)
    for test in TESTS:
        try:
            test()
        except Exception as exc:                                   # noqa: BLE001 - 测试汇总
            failures.append(test.__name__)
            print("FAIL  %s: %r" % (test.__name__, exc))
            traceback.print_exc()
        else:
            print("PASS  %s" % test.__name__)

    problems = []
    if sha256_of(SENTINEL_PATH) != sentinel_before:
        problems.append("测试改动了 %s" % SENTINEL_PATH)
    leftover = leftover_tmp_files()
    if leftover:
        problems.append("残留临时文件: %r" % (leftover,))

    print("-" * 60)
    if failures or problems:
        for p in problems:
            print("问题: %s" % p)
        print("失败 %d / %d 项测试%s"
              % (len(failures), len(TESTS), ("，未通过: %s" % ", ".join(failures)) if failures else ""))
        return 1
    print("全部 %d 项测试通过；src 哨兵哈希未变 (%s)，无残留临时文件"
          % (len(TESTS), sentinel_before[:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
