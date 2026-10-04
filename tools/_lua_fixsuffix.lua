local ok = pcall(function() Game:SetProperty("CSF_CopySuffix_8", " II") end)
local v = nil; pcall(function() v = Game:GetProperty("CSF_CopySuffix_8") end)
print("  设置 ok=" .. tostring(ok) .. "  现在=" .. tostring(v))
