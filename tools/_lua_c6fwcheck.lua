print("=== C6FW 检查 ===")
print("  C6FW = " .. type(C6FW))
if C6FW ~= nil then
  for _, k in ipairs({"HasGamePlayer","ActivatePlayer","GetPlayerColor","SetPlayerColor"}) do
    print(string.format("  C6FW.%-16s = %s", k, type(C6FW[k])))
  end
end
