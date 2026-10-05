local function try(f)
  local ok, v = pcall(f)
  if not ok then return "ERR(" .. tostring(v):sub(1,60) .. ")" end
  return tostring(v)
end
print("  LuaEvents = " .. try(function() return type(LuaEvents) end))
print("  LuaEvents.CSF_OpenPanel = " .. try(function() return type(LuaEvents.CSF_OpenPanel) end))
print("  Controls = " .. try(function() return type(Controls) end))
if LuaEvents ~= nil and LuaEvents.CSF_OpenPanel ~= nil then
  local ok, r = pcall(function() LuaEvents.CSF_OpenPanel(16, 26, nil, 0) end)
  print("  触发 CSF_OpenPanel ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
end
if Controls ~= nil and Controls.CSFRoot ~= nil then
  print("  CSFRoot 是否隐藏 = " .. try(function() return tostring(Controls.CSFRoot:IsHidden()) end))
end