# -*- coding: utf-8 -*-
"""在【游戏数据库副本】上逐条跑我们的 SQL，模拟引擎的"首错即停"。

为什么要这层验证：
  引擎逐语句执行、**首错即中止整份文件** —— 一条语句写错会让后面全部失效。
  在开游戏之前先在副本上跑一遍，能提前抓出：外键失败、列数不匹配、表不存在。

⚠️ 两个必须的桩：
  1. `Make_Hash` —— 引擎（DatabaseDLL）注册的自定义 SQL 函数，`Types` 表的
     触发器 `OnTypeInsert` 会调它算 Hash。Python 的 sqlite3 没有，必须自己注册，
     否则任何 `INSERT INTO Types` 都会报 "no such function: Make_Hash"。
     （本地用 FNV-1a 代替即可 —— 我们验的是外键/顺序逻辑，不是哈希值本身。）
  2. `PRAGMA foreign_keys=ON` —— 默认是关的，不开就验不出外键问题。
"""
import io, os, shutil, sqlite3, sys, tempfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def fnv1a32(s: str) -> int:
    """Make_Hash 的本地替身（引擎用哪个算法未知，这里只求非零且稳定）。"""
    h = 0x811C9DC5
    for ch in s.encode("utf-8"):
        h ^= ch
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h - 0x100000000 if h & 0x80000000 else h   # 转成有符号 32 位


def split_statements(raw: str) -> list[str]:
    """按 ';' 切分，先剥掉行注释与块注释。"""
    out_lines = []
    for ln in raw.splitlines():
        s = ln.strip()
        if s.startswith("--"):
            continue
        out_lines.append(ln)
    body = "\n".join(out_lines)
    return [s.strip() for s in body.split(";") if s.strip()]


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: _validate_sql.py <sql文件> [游戏数据库路径]")
        return 2
    sqlfile = sys.argv[1]
    src = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.environ["LOCALAPPDATA"],
        "Firaxis Games", "Sid Meier's Civilization VI", "Cache", "DebugGameplay.sqlite")

    if not os.path.exists(src):
        print(f"⚠️  找不到数据库: {src}")
        print("     （游戏至少启动过一次才会有这个缓存库）")
        return 3

    tmp = os.path.join(tempfile.gettempdir(), "csf_sqltest.sqlite")
    shutil.copy2(src, tmp)
    print(f"① 副本: {os.path.getsize(tmp)/1024/1024:.1f}MB -> {tmp}")

    conn = sqlite3.connect(tmp)
    conn.create_function("Make_Hash", 1, fnv1a32)      # ★ 桩
    conn.execute("PRAGMA foreign_keys=ON")             # ★ 开外键

    stmts = split_statements(open(sqlfile, encoding="utf-8").read())
    print(f"② 语句数: {len(stmts)}")

    failed = None
    for i, s in enumerate(stmts, 1):
        try:
            conn.execute(s)
        except Exception as exc:
            failed = (i, s, exc)
            break
    if failed:
        i, s, exc = failed
        print(f"③ ❌ 第 {i} 条失败: {exc}")
        print(f"   语句: {s[:160]}")
        return 1
    conn.commit()
    print(f"③ ✅ 全部 {len(stmts)} 条执行成功")

    # ── 验证结果 ─────────────────────────────────────────────────────────
    print("④ 结果核对:")
    civs = list(conn.execute(
        "SELECT CivilizationType, Name, StartingCivilizationLevelType "
        "FROM Civilizations WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%' "
        "ORDER BY CivilizationType"))
    print(f"   新建文明: {len(civs)} 个")
    for r in civs:
        print(f"     {r[0]:26} {r[1]:34} {r[2]}")

    traits = list(conn.execute(
        "SELECT LeaderType, TraitType FROM LeaderTraits "
        "WHERE LeaderType LIKE 'LEADER_MINOR_CIV_CSF_CS_%' ORDER BY LeaderType"))
    print(f"   能力挂载: {len(traits)} 条")
    from collections import Counter
    cnt = Counter(t for _, t in traits)
    for t, n in cnt.items():
        mark = "  ← ★ 多个城邦共用（能力重复）" if n > 1 else ""
        print(f"     {t:34} × {n}{mark}")

    types_n = conn.execute(
        "SELECT COUNT(*) FROM Types WHERE Type LIKE '%CSF_CS_%'").fetchone()[0]
    dup_n = conn.execute(
        "SELECT COUNT(*) FROM DuplicateCivilizations "
        "WHERE CivilizationType LIKE 'CIVILIZATION_CSF_CS_%'").fetchone()[0]
    hash_zero = conn.execute(
        "SELECT COUNT(*) FROM Types WHERE Hash=0 AND Type LIKE '%CSF_CS_%'").fetchone()[0]
    print(f"   Types 登记: {types_n} 条（Hash=0 的: {hash_zero}）")
    print(f"   别名登记:   {dup_n} 条")

    problems = []
    if len(civs) != 6:
        problems.append(f"文明数应为 6，实为 {len(civs)}")
    if types_n != 12:
        problems.append(f"Types 应为 12，实为 {types_n}")
    if hash_zero:
        problems.append(f"有 {hash_zero} 条 Hash=0（触发器的 Make_Hash 没被调用？）")
    if not any(n > 1 for n in cnt.values()):
        problems.append("没有任何两个城邦共用 Trait —— 能力重复没成立")

    print()
    if problems:
        print("⑤ ⚠️ 问题:")
        for p in problems:
            print(f"   - {p}")
        return 1
    print("⑤ ✅ 全部检查通过（含「能力重复」验证）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
