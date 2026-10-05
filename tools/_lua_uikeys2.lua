local keys = {}
for k, v in pairs(UI) do if type(k) == "string" and k >= "S" then keys[#keys+1] = k end end
table.sort(keys)
local line = ""
for _, s in ipairs(keys) do
  line = line .. s .. "  "
  if #line > 150 then print("UI2| " .. line); line = "" end
end
if #line > 0 then print("UI2| " .. line) end