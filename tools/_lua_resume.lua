print("=== t1 ===")
print("tostring(OnResumeGame)=" .. tostring(OnResumeGame))
print("tostring(Automation)=" .. tostring(Automation))
print("=== t2 ===")
if Automation ~= nil and Automation.SetAutoStartEnabled ~= nil then
  pcall(function() Automation.SetAutoStartEnabled(true) end)
  print("autostart on")
end
print("=== t3 ===")
if OnResumeGame ~= nil then
  local ok, err = pcall(OnResumeGame)
  print("OnResumeGame ok=" .. tostring(ok) .. " err=" .. tostring(err))
else
  print("OnResumeGame is nil")
end
print("=== done ===")
