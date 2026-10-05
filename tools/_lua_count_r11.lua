local t = nil
pcall(function() t = ExposedMembers.CSF.GetFoundableCityStates() end)
if type(t) ~= "table" then print("  ❌ 拿不到"); return end
local nReuse, nSlot, nUn, nTotal = 0, 0, 0, 0
for _, e in ipairs(t) do
  nTotal = nTotal + 1
  if e.Mode == "reuse" then nReuse = nReuse + 1
  elseif e.Mode == "slot" then nSlot = nSlot + 1
  else nUn = nUn + 1 end
end
print("  总数 = " .. nTotal)
print("  Mode=reuse  = " .. nReuse)
print("  Mode=slot   = " .. nSlot .. "   ← ★ 新增路径（应远多于 reuse）")
print("  其他        = " .. nUn)
print("  ★ 面板会列出 " .. (nReuse + nSlot) .. " 个")