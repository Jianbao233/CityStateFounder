# -*- coding: utf-8 -*-
"""把 `customcs` 探针插入 cs_probe.py（幂等：已存在则替换）。

为什么不直接编辑 cs_probe.py：那是个 8000 行的大文件，
用脚本插入比手工编辑可靠，而且可重复执行。

探针内容（全部只读，不改游戏状态）：
  ① GameInfo.Civilizations 里有没有我们那 6 个城邦
  ② 它们的 StartingCivilizationLevelType 是不是 CITY_STATE
  ③ 领袖与 LeaderTraits（★ 验证"能力重复"）
  ④ 本局玩家里有没有它们
  ⑤ DuplicateCivilizations 是否有我们的登记

⚠️ GameInfo 是按【字符串键】索引的（用哈希值索引会返回 nil）——
   这是本项目踩过的坑，探针里用字符串键。
"""
import io, re, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

PROBE_NAME = "customcs"

PROBE_LUA = r'''
P("==================== 自定义城邦验证 ====================")
P("")

-- ── ① 六个城邦是否注册进 GameInfo ────────────────────────────────────────
P("== [1] GameInfo.Civilizations 里的自定义城邦 ==")
local kWant = {
  "CIVILIZATION_CSF_CS_01", "CIVILIZATION_CSF_CS_02", "CIVILIZATION_CSF_CS_03",
  "CIVILIZATION_CSF_CS_04", "CIVILIZATION_CSF_CS_05", "CIVILIZATION_CSF_CS_06",
}
local kFound = {}
for _, sType in ipairs(kWant) do
  local row = safe(function() return GameInfo.Civilizations[sType] end)
  if row == nil then
    P(string.format("  ❌ %-24s 不存在", sType))
  else
    kFound[sType] = row
    P(string.format("  ✅ %-24s level=%-32s name=%s", sType,
      tostring(safe(function() return row.StartingCivilizationLevelType end)),
      tostring(safe(function() return row.Name end))))
  end
end
P(string.format("  → 找到 %d / %d", (function() local n=0 for _ in pairs(kFound) do n=n+1 end return n end)(), #kWant))

-- ── ② 领袖 + 能力（★ 核心：能力重复）──────────────────────────────────────
P("")
P("== [2] 领袖与 LeaderTraits（★ 能力重复验证）==")
local kTraitCount = {}
for _, sCiv in ipairs(kWant) do
  local sLeader = nil
  -- 从 CivilizationLeaders 反查领袖（GameInfo 是 Iterable）
  for row in GameInfo.CivilizationLeaders() do
    if row.CivilizationType == sCiv then sLeader = row.LeaderType break end
  end
  if sLeader == nil then
    P(string.format("  ❌ %-24s 没有 CivilizationLeaders 记录", sCiv))
  else
    local sTrait = nil
    for row in GameInfo.LeaderTraits() do
      if row.LeaderType == sLeader then sTrait = row.TraitType break end
    end
    P(string.format("  %-24s leader=%-32s trait=%s", sCiv, sLeader, tostring(sTrait)))
    if sTrait ~= nil then
      kTraitCount[sTrait] = (kTraitCount[sTrait] or 0) + 1
    end
  end
end
P("")
P("  能力分布（同一 Trait 被多个城邦共用 = 能力重复成立）:")
for sTrait, n in pairs(kTraitCount) do
  P(string.format("    %-36s × %d %s", sTrait, n, (n > 1) and "← ★ 重复" or ""))
end

-- ── ③ 本局玩家里有没有它们 ────────────────────────────────────────────────
P("")
P("== [3] 本局玩家中的自定义城邦 ==")
local iInGame = 0
for i = 0, 63 do
  local pc = safe(function() return PlayerConfigurations[i] end)
  if pc ~= nil then
    local sCiv = safe(function() return pc:GetCivilizationTypeName() end)
    if sCiv ~= nil and string.find(sCiv, "CSF_CS_") then
      iInGame = iInGame + 1
      P(string.format("  slot %2d  %-24s status=%s", i, sCiv,
        tostring(safe(function() return tostring(pc:GetSlotStatus()) end))))
    end
  end
end
if iInGame == 0 then
  P("  （本局没有 —— 原因是：城邦是开局按数量创建玩家时才分配文明，")
  P("    注册了 GameInfo 不等于本局就有。要它们出现需抬高城邦数量上限。）")
end

-- ── ④ DuplicateCivilizations 登记 ─────────────────────────────────────────
P("")
P("== [4] DuplicateCivilizations 登记（别名：允许与原版共存）==")
local iDup = 0
if GameInfo.DuplicateCivilizations ~= nil then
  for row in GameInfo.DuplicateCivilizations() do
    if string.find(tostring(row.CivilizationType), "CSF_CS_") then
      iDup = iDup + 1
      if iDup <= 6 then
        P(string.format("  %-24s ↔ %s", row.CivilizationType, row.OtherCivilizationType))
      end
    end
  end
  P(string.format("  → 共 %d 条", iDup))
else
  P("  ⚠️ GameInfo.DuplicateCivilizations 不存在")
end

-- ── ⑤ 文案 ────────────────────────────────────────────────────────────────
P("")
P("== [5] 文案是否解析（不是 raw 键）==")
for _, sTag in ipairs({"LOC_CSF_CS_01_NAME", "LOC_CSF_CS_03_NAME", "LOC_CSF_CS_05_NAME"}) do
  P(string.format("  %-24s -> %s", sTag, tostring(safe(function() return Locale.Lookup(sTag) end))))
end

P("")
P("==================== 验证结束 ====================")
'''

src = sys.argv[1] if len(sys.argv) > 1 else "cs_probe.py"
text = open(src, encoding="utf-8").read()

block = (
    "# ---- 25. 自定义城邦验证（能力重复 / 名字不同）------------------------\n"
    f'PROBES["{PROBE_NAME}"] = (\n'
    "    PRELUDE\n"
    "    + r\"\"\"\n"
    + PROBE_LUA
    + "\"\"\"\n"
    "    + EPILOGUE\n"
    ")\n"
)

marker = "# ---- 25. 自定义城邦验证"
if marker in text:
    # 替换到下一个顶层 "# ----" 之前
    start = text.index(marker)
    nxt = text.find("\n# ---- ", start + 1)
    end = nxt + 1 if nxt != -1 else len(text)
    text = text[:start] + block + text[end:]
    print(f"✅ 已替换 {PROBE_NAME} 探针")
else:
    # 插到最后一个 PROBES[...] 定义之后
    last = 0
    for m in re.finditer(r'^PROBES\["[a-z0-9_]+"\] = \(', text, re.M):
        last = m.start()
    if last == 0:
        print("❌ 找不到 PROBES 定义，未修改")
        sys.exit(1)
    # 找到该定义块的结尾（第一个顶格且非空的行之后）
    nxt = text.find("\n# ---- ", last + 1)
    end = nxt + 1 if nxt != -1 else len(text)
    text = text[:end] + "\n" + block + text[end:]
    print(f"✅ 已插入 {PROBE_NAME} 探针")

open(src, "w", encoding="utf-8", newline="\n").write(text)
print(f"   文件: {src}  （{len(text.splitlines())} 行）")
