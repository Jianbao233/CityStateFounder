local keys = {}
for k, v in pairs(UI) do
  if type(k) == "string" then keys[#keys+1] = k .. ":" .. type(v) end
end
table.sort(keys)
print("UI 键数 = " .. #keys)
local out, line = {}, ""
for _, s in ipairs(keys) do
  line = line .. s .. "  "
  if #line > 150 then out[#out+1] = line; line = "" end
end
if #line > 0 then out[#out+1] = line end
for _, l in ipairs(out) do print("UI| " .. l) end