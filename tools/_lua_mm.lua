print("=== MainMenu 状态里的 On*/Show* 函数 ===")
local names = {}
for k, v in pairs(_G) do
  if type(v) == "function" and (string.sub(k,1,2) == "On" or string.sub(k,1,4) == "Show" or string.find(k, "Game") or string.find(k, "Setup")) then
    names[#names+1] = k
  end
end
table.sort(names)
for _, k in ipairs(names) do print("  " .. k) end
print("  → 共 " .. #names .. " 个")
