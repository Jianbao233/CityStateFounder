print("=== 人类单位的可用方法（找 SetDone / 结束行动）===")
local p0 = Players[0]
if p0 == nil then print("  Players[0] = nil"); return end
local u0 = nil
pcall(function()
  for u in p0:GetUnits():Members() do u0 = u break end
end)
if u0 == nil then print("  没有单位"); return end
local ks = {}
pcall(function()
  for k, v in pairs(u0) do
    if type(v) == "function" then ks[#ks+1] = k end
  end
end)
table.sort(ks)
print("  单位方法（" .. #ks .. " 个）:")
for _, k in ipairs(ks) do print("    " .. k) end
print("")
print("=== 尝试 SetDone / 类似 ===")
for _, n in ipairs({ "SetDone", "SetTurnDone", "FinishMoves", "SetMovesRemaining", "SetHasMoved" }) do
  local ok, err = pcall(function() return u0[n](u0) end)
  print(string.format("  %-20s ok=%s err=%s", n, tostring(ok), tostring(err)))
end
