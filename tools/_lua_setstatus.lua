local iT = 15
print("  设 slot " .. iT .. " 的槽位状态为 1（AI）...")
local pm = nil
pcall(function() pm = WorldBuilder.PlayerManager() end)
print("  PlayerManager = " .. tostring(pm))
if pm ~= nil then
  local ok, r = pcall(function() return pm:SetPlayerSlotStatus(iT, 1) end)
  print("  SetPlayerSlotStatus ok=" .. tostring(ok) .. " 返回=" .. tostring(r))
end
local pc = nil; pcall(function() pc = PlayerConfigurations[iT] end)
if pc ~= nil then
  local st = nil; pcall(function() st = pc:GetSlotStatus() end)
  print("  现在的槽位状态 = " .. tostring(st))
end
local alive = nil; pcall(function() alive = Players[iT]:IsAlive() end)
print("  IsAlive = " .. tostring(alive))
print("  ★ 脚本正常结束")