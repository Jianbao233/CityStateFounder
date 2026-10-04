local function t(n) return type(_G[n]) end
print("state-probe: UI=" .. t("UI") .. " ActionTypes=" .. t("ActionTypes") .. " Game=" .. t("Game") .. " Players=" .. t("Players") .. " ExposedMembers=" .. t("ExposedMembers"))
if UI ~= nil then
  print("  UI.RequestAction = " .. type(UI.RequestAction))
end
if ActionTypes ~= nil then
  print("  ActionTypes.ACTION_ENDTURN = " .. tostring(ActionTypes.ACTION_ENDTURN))
end