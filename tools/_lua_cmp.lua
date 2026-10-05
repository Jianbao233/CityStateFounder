local function probe(iT)
  local pc, pl = nil, nil
  pcall(function() pc = PlayerConfigurations[iT] end)
  pcall(function() pl = Players[iT] end)
  if pc == nil or pl == nil then print("  slot " .. iT .. " 不存在"); return end
  local civ, alive, cn = nil, nil, 0
  pcall(function() civ = pc:GetCivilizationTypeName() end)
  pcall(function() alive = pl:IsAlive() end)
  pcall(function() cn = pl:GetCities():GetCount() end)
  print(string.format("  ── slot %d  %s  城市=%d ──", iT, tostring(civ), cn))
  local function chk(l, fn)
    local ok, v = pcall(fn)
    print(string.format("      %-24s %s", l, ok and tostring(v) or "ERR"))
  end
  chk("IsAlive", function() return pl:IsAlive() end)
  chk("IsMajor", function() return pl:IsMajor() end)
  chk("GetSlotStatus", function() return pc:GetSlotStatus() end)
  chk("GetPlayerType", function() return pc:GetPlayerType() end)
  chk("GetHandicap", function() return pc:GetHandicapTypeID() end)
  chk("GetDifficulty", function() return pc:GetDifficultyTypeID() end)
  -- 单位
  pcall(function()
    for _, u in pl:GetUnits():Members() do
      local ut, ux, uy, moves = nil, nil, nil, nil
      pcall(function() ut = GameInfo.Units[u:GetType()].UnitType end)
      pcall(function() ux = u:GetX() end)
      pcall(function() uy = u:GetY() end)
      pcall(function() moves = u:GetMovesRemaining() end)
      print(string.format("      单位 %s @ (%s,%s) 剩余移动=%s", tostring(ut), tostring(ux), tostring(uy), tostring(moves)))
      -- 能不能建城？
      if ut == "UNIT_SETTLER" then
        local ok2, b = pcall(function() return UnitManager.CanStartOperation(u, UnitOperationTypes.FOUND_CITY, nil, true) end)
        print("        可建城 = " .. tostring(ok2 and b or ("ERR:" .. tostring(b):sub(1,40))))
        local plot = nil
        pcall(function() plot = Map.GetPlot(ux, uy) end)
        if plot ~= nil then
          local own, water, mtn = nil, nil, nil
          pcall(function() own = plot:GetOwner() end)
          pcall(function() water = plot:IsWater() end)
          pcall(function() mtn = plot:IsMountain() end)
          print(string.format("        地块: owner=%s water=%s mountain=%s", tostring(own), tostring(water), tostring(mtn)))
        end
      end
    end
  end)
end
probe(15)
probe(9)