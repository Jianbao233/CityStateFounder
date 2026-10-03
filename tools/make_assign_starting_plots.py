#!/usr/bin/env python3
"""为 CityStateFounder 生成地图脚本：复制原生 AssignStartingPlots.lua 并打补丁。

补丁点（原生 Base\\Assets\\Maps\\Utility\\AssignStartingPlots.lua:280-295）：
    城邦获得起始点的唯一位置 —— player:SetStartingPlot(v)

改造目标：
    预留的一部分城邦【不调 SetStartingPlot】（引擎就不为它在地图上生成单位
    → 没有起始位置），改为在【地图外】放一个移民（-1,-1，引擎会落到
    (-9999,-9999)）→ 有单位 → 不会灭亡。

依据：
    Free City States 的注释："this should happen even before city state unit
    spawn on map … so they do not have a starting position"
    本项目实测 T-62：这样造出的休眠城邦可稳定存活 50 回合且保持 0 城

用法：python make_assign_starting_plots.py
"""

from __future__ import annotations

import sys
from pathlib import Path

VANILLA = Path(
    r"F:\Steam\steamapps\common\Sid Meier's Civilization VI"
    r"\Base\Assets\Maps\Utility\AssignStartingPlots.lua"
)
OUT = Path(__file__).resolve().parent.parent / "src" / "Map" / "CSF_AssignStartingPlots.lua"

# 原生片段（注意：文件用 Tab 缩进）
ANCHOR = (
    b"\tfor i = 1, self.iNumMinorCivs do\r\n"
    b"\t\tlocal player = Players[self.minorList[i]]\r\n"
)
if ANCHOR not in VANILLA.read_bytes():
    ANCHOR = ANCHOR.replace(b"\r\n", b"\n")   # 兼容 LF

# ⚠️ 必须精确锚定【城邦】那一处！
#    全文有 3 处 SetStartingPlot，第一次出现的是【主文明】路径
#    （紧随其后打印 "Major Start X"）。城邦路径紧随其后打印 "Minor Start X"。
#    早先版本用"第一次出现"替换，误伤了主文明 —— 靠后续 print 行消歧。
SET_START = (
    b"\t\t\t\t\tplayer:SetStartingPlot(v);\r\n"
    b"\t\t\t\t\tprint(\"Minor Start X: \", v:GetX(), \"Minor Start Y: \", v:GetY());"
)

HEADER = """-- ===========================================================================
-- CityStateFounder / 城邦缔造者 —— AssignStartingPlots 覆盖版
--
-- 本文件 = 原生 Base/Assets/Maps/Utility/AssignStartingPlots.lua + CSF 补丁
-- 补丁位置：__SetStartMinor() 里给城邦分配起始点处（原生 :280-295）
--
-- CSF 改动（仅此两处，其余与原生完全一致）：
--   1) 在给城邦分配起始点【之前】，对预留城邦调用
--        UnitManager.InitUnit(id, "UNIT_SETTLER", -1, -1)
--      —— 地图外放一个移民，保证它"有单位所以不灭亡"
--   2) 对预留城邦【跳过】 player:SetStartingPlot(v)
--      —— 引擎就不会为它在地图上生成单位，因此它没有起始位置，
--         也就不会自己建城（= 休眠城邦）
--
-- ⚠️ CSF_RESERVED_COUNT 必须与 Data/CSF_MapSizes.sql 的 +N 保持一致
-- ===========================================================================

local CSF_RESERVED_COUNT = 12;

-- 判断第 i 个城邦（在 self.minorList 中的序号）是否属于预留槽位
local function CSF_IsReservedMinor(self, i)
    if CSF_RESERVED_COUNT <= 0 then return false end
    return i > (self.iNumMinorCivs - CSF_RESERVED_COUNT);
end

-- 把预留城邦送下地图：地图外给移民 + 杀掉地图上已有的单位
local function CSF_SendOffMap(iPlayerID)
    -- 地图外生成（引擎会把坐标落到 (-9999,-9999)）
    UnitManager.InitUnit(iPlayerID, "UNIT_SETTLER", -1, -1);
    local pUnits = Players[iPlayerID]:GetUnits();
    for _, pUnit in pUnits:Members() do
        local x, y = pUnit:GetX(), pUnit:GetY();
        if x >= 0 or y >= 0 then
            UnitManager.Kill(pUnit, false);
        end
    end
    print("CSF: city-state " .. tostring(iPlayerID) .. " reserved off-map");
end

""".encode("utf-8")

PATCH_SET_START = (
    b"\t\t\t\t\t-- CSF: \xe9\xa2\x84\xe7\x95\x99\xe5\x9f\x8e\xe9\x82\xa6\xe4\xb8\x8d\xe8\x90\xbd\xe5\x9c\xb0\r\n"
    b"\t\t\t\t\tif not CSF_IsReservedMinor(self, i) then\r\n"
    b"\t\t\t\t\t\tplayer:SetStartingPlot(v);\r\n"
    b"\t\t\t\t\tend\r\n"
    b"\t\t\t\t\tprint(\"Minor Start X: \", v:GetX(), \"Minor Start Y: \", v:GetY());"
)

PATCH_SET_START_LF = PATCH_SET_START.replace(b"\r\n", b"\n")


def main() -> None:
    if not VANILLA.exists():
        print(f"[FAIL] 找不到原生文件: {VANILLA}")
        sys.exit(2)

    data = VANILLA.read_bytes()
    eol = b"\r\n" if b"\r\n" in data[:2000] else b"\n"
    print(f"原生文件 {len(data)} 字节，行尾 = {'CRLF' if eol == b'\\r\\n' else 'LF'}")

    anchor = ANCHOR if eol == b"\r\n" else ANCHOR.replace(b"\r\n", b"\n")
    setstart = PATCH_SET_START if eol == b"\r\n" else PATCH_SET_START_LF

    if anchor not in data:
        print("[FAIL] 未找到 __SetStartMinor 的循环锚点")
        sys.exit(2)
    if SET_START not in data:
        print("[FAIL] 未找到 player:SetStartingPlot(v); 锚点")
        sys.exit(2)

    # ① 在城邦循环【之前】插入"把预留城邦送下地图"
    insert = (
        b"\t-- ===== CSF PATCH 1: \xe6\x8a\x8a\xe9\xa2\x84\xe7\x95\x99\xe5\x9f\x8e\xe9\x82\xa6\xe9\x80\x81\xe4\xb8\x8b\xe5\x9c\xb0\xe5\x9b\xbe =====\r\n"
        b"\tfor i = 1, self.iNumMinorCivs do\r\n"
        b"\t\tif CSF_IsReservedMinor(self, i) then\r\n"
        b"\t\t\tCSF_SendOffMap(self.minorList[i]);\r\n"
        b"\t\tend\r\n"
        b"\tend\r\n"
        b"\r\n"
    )
    if eol != b"\r\n":
        insert = insert.replace(b"\r\n", b"\n")
    data = data.replace(anchor, insert + anchor, 1)

    # ② 给 SetStartingPlot 加预留判断
    data = data.replace(SET_START, setstart, 1)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(HEADER + data)
    print(f"[OK] 已写出 {OUT}  ({OUT.stat().st_size} 字节)")

    # 自检
    out = OUT.read_bytes()
    print(f"  含 CSF_RESERVED_COUNT      : {b'CSF_RESERVED_COUNT' in out}")
    print(f"  含 CSF_SendOffMap          : {b'CSF_SendOffMap' in out}")
    print(f"  含 CSF_IsReservedMinor 判断: {out.count(b'CSF_IsReservedMinor')} 处")
    print(f"  SetStartingPlot 出现次数   : {out.count(b'player:SetStartingPlot')}")


if __name__ == "__main__":
    main()
