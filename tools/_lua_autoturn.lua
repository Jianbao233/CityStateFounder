print("=== Automation 模块的方法 ===")
if Automation ~= nil then
  local ks = {}
  for k, v in pairs(Automation) do ks[#ks+1] = k .. "(" .. type(v) .. ")" end
  table.sort(ks)
  for _, k in ipairs(ks) do print("  " .. k) end
else
  print("  Automation = nil")
end
print("")
print("=== Options / AppOptions ===")
for _, n in ipairs({ "Options", "AppOptions", "UserOptions", "GameOptions" }) do
  local v = nil
  pcall(function() v = _G[n] end)
  print(string.format("  %-14s = %s", n, type(v)))
end
print("")
print("=== 找含 Turn 的全局/模块 ===")
for _, n in ipairs({ "Automation", "Game", "Players", "UI" }) do
  local m = nil
  pcall(function() m = _G[n] end)
  if m ~= nil then
    local hits = {}
    pcall(function()
      for k, v in pairs(m) do
        if string.find(string.lower(tostring(k)), "turn") then hits[#hits+1] = k end
      end
    end)
    if #hits > 0 then print("  " .. n .. ": " .. table.concat(hits, ", ")) end
  end
end
