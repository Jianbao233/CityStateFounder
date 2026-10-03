print("=== 本局概况 ===")
print("  玩家数(有文明的槽) = " .. (function() local n=0; for i=0,63 do local pc=nil; pcall(function() pc=PlayerConfigurations[i] end); if pc then local c=nil; pcall(function() c=pc:GetCivilizationTypeName() end); if c and c~="" then n=n+1 end end end; return n end)())
print("  城邦玩家(AliveMinors) = " .. tostring(#(PlayerManager.GetAliveMinorIDs() or {})))
print("  UNIT_CSF_ENVOY 存在 = " .. tostring(GameInfo.Units["UNIT_CSF_ENVOY"] ~= nil))
local nCS = 0
for _, id in ipairs(PlayerManager.GetAliveMinorIDs() or {}) do
  local p = Players[id]
  if p ~= nil then
    local c = 0; pcall(function() c = p:GetCities():GetCount() end)
    if c == 0 then nCS = nCS + 1 end
  end
end
print("  休眠城邦(0城) = " .. nCS)
