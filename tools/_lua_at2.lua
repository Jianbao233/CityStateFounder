local out = {}
out[#out+1] = "UI=" .. type(UI)
out[#out+1] = "ActionTypes=" .. type(ActionTypes)
out[#out+1] = "_G=" .. type(_G)
if _G ~= nil then
  local keys = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and (string.find(k, "Action") or string.find(k, "ACTION")) then
      keys[#keys+1] = k .. "(" .. type(v) .. ")"
    end
  end
  table.sort(keys)
  out[#out+1] = "ActionKeys[" .. #keys .. "]=" .. table.concat(keys, ",")
end
if UI ~= nil then
  local uk = {}
  for k, v in pairs(UI) do
    if type(k) == "string" and (string.find(k, "Action") or string.find(k, "Turn")) then
      uk[#uk+1] = k
    end
  end
  table.sort(uk)
  out[#out+1] = "UIKeys=" .. table.concat(uk, ",")
end
print("PROBE " .. table.concat(out, " || "))