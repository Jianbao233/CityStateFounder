import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ── 已知数据 ────────────────────────────────────────────────────────────────
# Civ6 各地图规格的网格尺寸（W x H）
SIZES = [
    ("决斗 Duel",     44,  26,  6,  3),
    ("极小 Tiny",     60,  38, 10,  6),
    ("小 Small",      74,  46, 14,  9),
    ("标准 Standard", 84,  54, 18, 12),
    ("大 Large",      96,  60, 22, 15),
    ("巨大 Huge",    106,  66, 24, 18),
]

# 各规格的默认主文明数（DefaultPlayers，来自 MapSizes.xml）
DEFAULT_MAJORS = {
    "决斗 Duel": 2, "极小 Tiny": 4, "小 Small": 6,
    "标准 Standard": 8, "大 Large": 10, "巨大 Huge": 12,
}

# CCB Maps 的阻塞半径（来自 BBM_MapUtils.lua:859-860 的 GlobalParameters）
R_CS_TO_CS  = 7   # START_DISTANCE_MINOR_CIVILIZATION_START
R_MAJOR_TO_CS = 8 # START_DISTANCE_MINOR_MAJOR_CIVILIZATION

def ring_area(r):
    """六边形半径 r 内的格数"""
    return 3 * r * (r + 1) + 1

def packing_area(r):
    """最小中心间距 r 时，每个中心平均占用（六方最密堆积，含边界折扣）"""
    import math
    return r * r * math.sqrt(3) / 2

print("=" * 92)
print("CCB Maps（BBS Maps）城邦容量推算")
print("=" * 92)
print()
print("【阻塞半径来源】BBM_MapUtils.lua:859-860")
print(f"  城邦 → 城邦   = START_DISTANCE_MINOR_CIVILIZATION_START  = {R_CS_TO_CS}")
print(f"  主文明 → 城邦 = START_DISTANCE_MINOR_MAJOR_CIVILIZATION  = {R_MAJOR_TO_CS}")
print()
print(f"  半径 {R_CS_TO_CS} 的六边形 = {ring_area(R_CS_TO_CS)} 格")
print(f"  半径 {R_MAJOR_TO_CS} 的六边形 = {ring_area(R_MAJOR_TO_CS)} 格")
print()

print("=" * 92)
print("【推算表】")
print("=" * 92)
print()
hdr = f"{'规格':<16}{'网格':<12}{'总格数':>8}{'主文明':>7}{'主文明阻塞':>11}{'剩余':>8}{'理论城邦':>10}{'官方上限':>10}"
print(hdr)
print("-" * 92)

results = []
for name, w, h, official_max, official_def in SIZES:
    total = w * h
    majors = DEFAULT_MAJORS[name]
    major_block = majors * ring_area(R_MAJOR_TO_CS)
    remain = max(0, total - major_block)
    cs_cap = remain / ring_area(R_CS_TO_CS)
    results.append((name, w, h, total, majors, major_block, remain, cs_cap, official_max))
    print(f"{name:<16}{f'{w}x{h}':<12}{total:>8}{majors:>7}{major_block:>11}{remain:>8}{cs_cap:>10.1f}{official_max:>10}")

print()
print("=" * 92)
print("【实测校准】")
print("=" * 92)
print()
print("  用户实测：标准图（84x54）拉满 18 → CCB Maps 放到第 18 个时崩，")
print("            即【只能放下 17 个】。")
print()
for name, w, h, total, majors, major_block, remain, cs_cap, official_max in results:
    if "标准" in name:
        print(f"  本表推算：{cs_cap:.1f}   实测：17   偏差：{abs(cs_cap-17):.1f}")
        ratio = 17 / cs_cap
        print(f"  → 实测/推算 = {ratio:.2f}（可作全局校准系数）")
        print()
        print("=" * 92)
        print("【校准后的建议上限】（推算值 × 0.85，留安全余量）")
        print("=" * 92)
        print()
        print(f"{'规格':<16}{'推算':>8}{'建议安全值':>12}{'官方上限':>10}{'说明':<28}")
        print("-" * 92)
        for n2, w2, h2, t2, m2, mb2, r2, c2, om2 in results:
            safe = int(c2 * 0.85)
            note = ""
            if safe >= om2:
                note = "官方上限本身就在容量内 ✅"
            else:
                note = f"比官方上限低 {om2 - safe}"
            print(f"{n2:<16}{c2:>8.1f}{safe:>12}{om2:>10}  {note:<28}")
