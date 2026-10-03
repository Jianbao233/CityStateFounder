-- 取本局 6 个自定义城邦的【显示名】与【宗主加成名】——证明"名字不同、能力相同"
print("=== 自定义城邦：名字 + 能力（本局实际玩家）===")
local rows = {}
for i = 0, 63 do
  local pc = nil
  pcall(function() pc = PlayerConfigurations[i] end)
  if pc ~= nil then
    local sCiv = nil
    pcall(function() sCiv = pc:GetCivilizationTypeName() end)
    if sCiv ~= nil and string.find(sCiv, "CSF_CS_") then
      local sLeader = nil
      pcall(function() sLeader = pc:GetLeaderTypeName() end)
      -- 文明显示名（从 GameInfo 取 Name 键，再本地化）
      local sCivNameKey, sCivName = nil, "?"
      pcall(function()
        for row in GameInfo.Civilizations() do
          if row.CivilizationType == sCiv then sCivNameKey = row.Name break end
        end
      end)
      if sCivNameKey ~= nil then
        pcall(function() sCivName = Locale.Lookup(sCivNameKey) end)
      end
      -- 该玩家实际的 Trait（引擎侧）
      local sTrait, sTraitName = nil, "?"
      pcall(function()
        for row in GameInfo.LeaderTraits() do
          if row.LeaderType == sLeader then sTrait = row.TraitType break end
        end
      end)
      if sTrait ~= nil then
        pcall(function()
          for row in GameInfo.Traits() do
            if row.TraitType == sTrait then sTraitName = Locale.Lookup(row.Name) break end
          end
        end)
      end
      rows[#rows+1] = {i = i, civ = sCiv, name = sCivName, leader = sLeader,
                       trait = sTrait, traitName = sTraitName}
    end
  end
end

table.sort(rows, function(a, b) return a.civ < b.civ end)
for _, r in ipairs(rows) do
  print(string.format("  slot %2d | %-24s | 显示名=%-10s | 加成=%s",
        r.i, r.civ, tostring(r.name), tostring(r.traitName)))
  print(string.format("           trait=%s", tostring(r.trait)))
end

print("")
print("=== 按加成分组（同一加成多个城邦 = 能力重复）===")
local grp = {}
for _, r in ipairs(rows) do
  local k = tostring(r.trait)
  grp[k] = grp[k] or {}
  table.insert(grp[k], tostring(r.name))
end
for k, v in pairs(grp) do
  print(string.format("  %-34s × %d  →  %s", k, #v, table.concat(v, " / ")))
end
