print("=== ExposedMembers.CSF 暴露了什么 ===")
if ExposedMembers == nil then print("  ExposedMembers = nil"); return end
if ExposedMembers.CSF == nil then print("  ExposedMembers.CSF = nil"); return end
local ks = {}
for k, v in pairs(ExposedMembers.CSF) do ks[#ks+1] = k .. " (" .. type(v) .. ")" end
table.sort(ks)
for _, k in ipairs(ks) do print("  " .. k) end
