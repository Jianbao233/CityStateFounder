local o = {}
o[#o+1] = "AT=" .. type(ActionTypes)
o[#o+1] = "DET=" .. type(DoEndTurn)
o[#o+1] = "UI=" .. type(UI)
if ActionTypes ~= nil then o[#o+1] = "ENDTURN=" .. tostring(ActionTypes.ACTION_ENDTURN) end
print("SCAN " .. table.concat(o, " "))