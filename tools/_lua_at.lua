local out = {}
out[#out+1] = "UI=" .. type(UI)
out[#out+1] = "ActionTypes=" .. type(ActionTypes)
if ActionTypes ~= nil then out[#out+1] = "ENDTURN=" .. tostring(ActionTypes.ACTION_ENDTURN) end
if _G ~= nil then
  local n = 0
  for k, v in pairs(_G) do
    if type(k) == "string" and string.find(k, "Action") then n = n + 1; if n <= 5 then out[#out+1] = "G:" .. k .. "=" .. type(v) end end
  end
end
print("PROBE " .. table.concat(out, " | "))