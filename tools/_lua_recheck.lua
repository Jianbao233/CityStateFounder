print("=== 那烂陀（slot 19）复查 ===")
local i = 19
local function chk(l, f) local ok,v = pcall(f) print(string.format("  %-30s %s", l, ok and tostring(v) or ("ERR:"..tostring(v)))) end
chk("IsAlive", function() return Players[i]:IsAlive() end)
chk("GetCities():GetCount()", function() return Players[i]:GetCities():GetCount() end)
chk("GetCapitalCity()", function() return Players[i]:GetCities():GetCapitalCity() end)
chk("首都名", function() return Locale.Lookup(Players[i]:GetCities():GetCapitalCity():GetName()) end)
chk("首都坐标", function() local c=Players[i]:GetCities():GetCapitalCity() return c:GetX()..","..c:GetY() end)
chk("首都人口", function() return Players[i]:GetCities():GetCapitalCity():GetPopulation() end)
chk("GetColor()", function() return PlayerConfigurations[i]:GetColor() end)
chk("GetDiplomacy()", function() return Players[i]:GetDiplomacy() end)
chk("GetInfluence()", function() return Players[i]:GetInfluence() end)
chk("IsMajor", function() return Players[i]:IsMajor() end)
chk("GetLeaderName()", function() return PlayerConfigurations[i]:GetLeaderName() end)
