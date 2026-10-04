-- ===========================================================================
-- CSF_BannerColorFix.lua —— 旗标颜色兜底（★ 只包装 UI.GetPlayerColors）
-- ===========================================================================
-- 目的：让【中途建出来的城邦】旗标颜色正常，且不触发
--       `CityBannerManager: Called SetColor with nil value` → 引擎崩溃。
--
-- 根因（实测 + 逆向）：
--   · 中途激活/新建的玩家**不在 UI 的颜色表里** → `UI.GetPlayerColors(slot)` 返回 nil
--   · 旗标代码直接把这个 nil 传给 `SetColor()` → 崩溃
--     （引擎日志：CityBannerManager: Called SetColor with nil value. ×4 后崩）
--
-- ── ⚠️⚠️⚠️ 两次走弯路的记录（别再犯）────────────────────────────────────
--   ① 第一次：照抄 `Base\Assets\UI\WorldView\CityBannerManager.lua` 的 UpdateColor
--      逐行重写 → 但游戏实际加载的是
--      `DLC\Expansion2\UI\CityBanners\CityBannerManager.lua`，两者控件不同
--      → `self.m_Instance.CityPopulation` 是 nil → 每帧报错 → 城市面板消失。
--   ② 第二次：给每个 SetColor 加 nil 守卫 → 不崩了，但
--      **旗标整个不显示**（因为 XP2 版原函数还负责显示/隐藏旗标，我的重写没做）。
--
--   → 结论：**根本不该替换 CityBannerManager。**
--     正确做法是只包装 `UI.GetPlayerColors` —— 旗标代码一行都不用改，
--     它自己就能拿到颜色；显示逻辑完全由原版负责。
--
-- 手法参考：CCB MirrorMap 的 UI\CityBannerManager_Mirror.lua:7-13
--   （它也是在取色处兜底，而不是重写整个绘制流程）
--
-- ⚠️ 本文件运行在 **InGame（UI）上下文**（`UI` 表在那里可用）。
-- ===========================================================================

-- 保存原函数（幂等：重复加载时不要包两层）
if CSF_OrigGetPlayerColors == nil and UI ~= nil and UI.GetPlayerColors ~= nil then
    CSF_OrigGetPlayerColors = UI.GetPlayerColors;

    --- 取一个玩家的旗标颜色；UI 表里没有（nil）时逐级兜底。
    -- @return backColor, frontColor（绝不为 nil —— 这是防崩的关键）
    UI.GetPlayerColors = function(playerID)
        local backColor, frontColor = CSF_OrigGetPlayerColors(playerID);
        if backColor ~= nil and frontColor ~= nil then
            return backColor, frontColor;          -- 正常情况，原样返回
        end

        -- 只有"中途建出来的"玩家才兜底（用 Game 属性标记过）
        local sSourceCiv = nil;
        pcall(function()
            if CSF_GetCopySource ~= nil then
                sSourceCiv = CSF_GetCopySource(playerID);
            end
            if sSourceCiv == nil and CSF_GetGameProp ~= nil then
                sSourceCiv = CSF_GetGameProp("CSF_Created_" .. tostring(playerID));
            end
        end);

        -- ① 找【正在使用同一文明】的玩家，用它的颜色（最准）
        local sCiv = sSourceCiv;
        if sCiv == nil then
            pcall(function()
                sCiv = PlayerConfigurations[playerID]:GetCivilizationTypeName();
            end);
        end
        if sCiv ~= nil then
            for i = 0, 63 do
                if i ~= playerID then
                    local b2, f2 = nil, nil;
                    pcall(function()
                        local c2 = PlayerConfigurations[i]:GetCivilizationTypeName();
                        if c2 == sCiv then b2, f2 = CSF_OrigGetPlayerColors(i) end
                    end);
                    if b2 ~= nil and f2 ~= nil then
                        print("[CSF] banner color: slot " .. tostring(playerID) ..
                              " 用同文明槽 " .. tostring(i) .. " 的颜色兜底");
                        return b2, f2;
                    end
                end
            end
            -- ② 按【文明】取色（城邦颜色是按文明定义的，实测可用）
            local b3, f3 = nil, nil;
            pcall(function() b3, f3 = UI.GetPlayerColorValues(sCiv, 0) end);
            if b3 ~= nil and f3 ~= nil then
                print("[CSF] banner color: slot " .. tostring(playerID) ..
                      " 用文明色兜底（" .. tostring(sCiv) .. "）");
                return b3, f3;
            end
        end

        -- ③ 最后一道保险：绝不让 SetColor 拿到 nil
        print("[CSF] banner color: slot " .. tostring(playerID) .. " 三级兜底失败，用安全色");
        return 0xFF202020, 0xFFC0C0C0;
    end;

    print("[CSF] CSF_BannerColorFix.lua loaded（包装 UI.GetPlayerColors，不动 CityBannerManager）");
else
    print("[CSF] CSF_BannerColorFix.lua: 跳过（UI.GetPlayerColors 不可用或已包装）");
end
