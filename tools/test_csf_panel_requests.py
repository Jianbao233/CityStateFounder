"""Offline execution of the real panel callbacks, without a game or network."""
import unittest
from pathlib import Path

from lupa import LuaRuntime

PANEL = Path(__file__).resolve().parents[1] / "src/UI/CSF_Panel.lua"
TEXT = Path(__file__).resolve().parents[1] / "src/Text/CSF_Text.xml"

STUBS = r'''
print = function() end
include = function() end
W = {requests=0, envoys=0, result={0,false,"none",-1,-1,-1},
     foundable={{Civ="CIV_TEST",Mode="slot",Name="Test",CanReceiveInfluence=true}},
     stats={total=5,dormant=1,active=1,pending=3,pool=48}}
local function control()
    return setmetatable({hidden=false,disabled=false,text=""}, {__index=function(t,k)
        if k=="SetHide" then return function(self,v) self.hidden=v end end
        if k=="IsHidden" then return function(self) return self.hidden end end
        if k=="SetDisabled" then return function(self,v) self.disabled=v end end
        if k=="SetText" then return function(self,v) self.text=v end end
        return function() end
    end})
end
Controls = setmetatable({}, {__index=function(t,k) local v=control();rawset(t,k,v);return v end})
InstanceManager = {new=function() return {
    ResetInstances=function() end,
    GetInstance=function() return setmetatable({}, {__index=function(t,k)
        local v=control();rawset(t,k,v);return v end}) end
} end}
Mouse = {eLClick=1}
Locale = {Lookup=function(s) return s end}
UIManager = {QueuePopup=function() end,DequeuePopup=function() end}
PopupPriority = {Current=1}
Game = {GetLocalPlayer=function() return 0 end,GetProperty=function()return W.sequence or 0 end}
PlayerOperations = {PARAM_PLAYER_ONE="target",GIVE_INFLUENCE_TOKEN=1,EXECUTE_SCRIPT=2}
UI = {RequestPlayerOperation=function(owner,op,params)
    if op==1 then W.envoys=W.envoys+1;return true end
    assert(op==2 and params.OnStart=='CSF_FoundRequest')
    W.requests=W.requests+1;W.owner=owner;W.params=params
    if W.accepted==false then return false end
    W.sequence=params.CSF_RequestID
    if W.onOperation then W.onOperation(owner,params)end
    return true
end}
LuaEvents = {CSF_OpenPanel={Add=function() end}}
GameEvents = {CSF_FoundResult={Add=function(f) W.event=f end}}
Keys = {VK_ESCAPE=27,VK_E=69,VK_R=82}
ContextPtr = {
    SetInitHandler=function(self,f) W.init=f end,
    SetShutdown=function() end,
    SetUpdate=function(self,f) W.update=f end,
    SetInputHandler=function() end
}
ExposedMembers = {CSF={
    GetFoundableCityStates=function() return W.foundable end,
    GetGameCityStateStats=function() return W.stats end,
    RequestFound=function()error('UI must use native synchronized operation')end,
    GetLastResult=function() return table.unpack(W.result) end
}}
function open_panel()
    CSF_OpenAt(10,11,99,0)
    CSF_SelectEntry("CIV_TEST")
end
function result(seq,success,request,owner)
    W.result={seq,success,success and "ok" or "water",23,10,11,request,owner}
end
function emit(success,request,owner)
    W.event(success,success and "ok" or "water",23,10,11,request,owner)
end
'''


class PanelRequests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUBS)
        self.lua.execute(PANEL.read_text(encoding="utf-8"))
        self.lua.execute("W.init();open_panel()")

    def evaluate(self, code):
        return self.lua.eval(code)

    def test_initial_none_does_not_end_pending_request(self):
        self.lua.execute("CSF_OnConfirm();W.update()")
        self.assertTrue(self.evaluate("Controls.CSFConfirmButton.disabled"))
        self.assertEqual(self.evaluate("Controls.CSFHint.text"), "LOC_CSF_PANEL_PENDING")
        self.assertEqual(self.evaluate("W.envoys"), 0)

    def test_stale_poll_and_broadcast_cannot_complete_request(self):
        self.lua.execute("CSF_OnConfirm();result(100,true,88,0);W.update();emit(true,88,0)")
        self.assertTrue(self.evaluate("Controls.CSFConfirmButton.disabled"))
        self.assertFalse(self.evaluate("Controls.CSFRoot.hidden"))
        self.assertEqual(self.evaluate("W.envoys"), 0)

    def test_other_player_result_is_ignored(self):
        self.lua.execute("CSF_OnConfirm();result(1,true,1,4);W.update();emit(true,1,4)")
        self.assertTrue(self.evaluate("Controls.CSFConfirmButton.disabled"))
        self.assertEqual(self.evaluate("W.envoys"), 0)

    def test_double_confirm_queues_once(self):
        self.lua.execute("CSF_OnConfirm();CSF_OnConfirm()")
        self.assertEqual(self.evaluate("W.requests"), 1)

    def test_foreign_owner_is_not_submitted(self):
        self.lua.execute('CSF_OpenAt(10,11,99,4);CSF_SelectEntry("CIV_TEST");CSF_OnConfirm()')
        self.assertEqual(self.evaluate('W.requests'), 0)

    def test_native_request_rejection_does_not_leave_panel_waiting(self):
        self.lua.execute('W.accepted=false;CSF_OnConfirm()')
        self.assertFalse(self.evaluate('Controls.CSFConfirmButton.disabled'))

    def test_fast_native_completion_is_not_overwritten(self):
        self.lua.execute('W.onOperation=function(owner,p)emit(true,p.CSF_RequestID,owner)end;CSF_OnConfirm()')
        self.assertTrue(self.evaluate('Controls.CSFRoot.hidden'))
        self.assertFalse(self.evaluate('Controls.CSFConfirmButton.disabled'))

    def test_failure_then_retry_in_same_panel(self):
        self.lua.execute("CSF_OnConfirm();result(1,false,1,0);W.update()")
        self.assertFalse(self.evaluate("Controls.CSFConfirmButton.disabled"))
        self.assertFalse(self.evaluate("Controls.CSFRoot.hidden"))
        self.lua.execute("CSF_OnConfirm();result(2,true,2,0);W.update()")
        self.assertTrue(self.evaluate("Controls.CSFRoot.hidden"))
        self.assertEqual(self.evaluate("W.requests"), 2)
        self.assertEqual(self.evaluate("W.envoys"), 0)  # 奖励由 Gameplay 发放

    def test_poll_and_event_success_are_deduplicated(self):
        self.lua.execute("CSF_OnConfirm();emit(true,1,0);result(1,true,1,0);W.update();emit(true,1,0)")
        self.assertTrue(self.evaluate("Controls.CSFRoot.hidden"))
        self.assertEqual(self.evaluate("W.envoys"), 0)

    def test_late_result_after_reopening_cannot_complete_new_request(self):
        self.lua.execute("CSF_OnConfirm();CSF_Close();open_panel();CSF_OnConfirm();emit(true,1,0)")
        self.assertTrue(self.evaluate("Controls.CSFConfirmButton.disabled"))
        self.assertEqual(self.evaluate("W.envoys"), 0)
        self.lua.execute("emit(true,2,0)")
        self.assertTrue(self.evaluate("Controls.CSFRoot.hidden"))
        self.assertEqual(self.evaluate("W.envoys"), 0)

    def refresh_with(self, foundable, stats="W.stats"):
        self.lua.execute(
            f"W.foundable={foundable};W.stats={stats};CSF_Refresh()"
        )

    def test_full_capacity_uses_dedicated_no_slot_reason(self):
        self.refresh_with(
            '{{Civ="CIV_A",Mode="unavailable",UnavailableReason="no_free_slot"},'
            '{Civ="CIV_B",Mode="unavailable",UnavailableReason="no_free_slot"}}'
        )
        self.assertEqual(self.evaluate("Controls.CSFHint.text"),
                         "LOC_CSF_REASON_NO_SLOT")

    def test_missing_bridge_is_not_reported_as_capacity_exhaustion(self):
        self.refresh_with(
            '{{Civ="CIV_A",Mode="unavailable",UnavailableReason="native_unavailable"}}'
        )
        hint = self.evaluate("Controls.CSFHint.text")
        self.assertEqual(hint, "LOC_CSF_PANEL_NO_POOL")
        self.assertNotEqual(hint, "LOC_CSF_REASON_NO_SLOT")

    def test_mixed_or_unknown_unavailable_reason_is_general_message(self):
        self.refresh_with(
            '{{Civ="CIV_A",Mode="unavailable",UnavailableReason="no_free_slot"},'
            '{Civ="CIV_B",Mode="unavailable"}}'
        )
        self.assertEqual(self.evaluate("Controls.CSFHint.text"),
                         "LOC_CSF_PANEL_NO_POOL")

    def test_stats_show_active_cities_not_total_or_pool(self):
        self.refresh_with(
            '{{Civ="CIV_TEST",Mode="slot",Name="Test",CanReceiveInfluence=true}}',
            "{total=99,dormant=50,active=4,pending=45,pool=48}",
        )
        hint = self.evaluate("Controls.CSFHint.text")
        self.assertIn("LOC_CSF_PANEL_COUNT_MID 4 LOC_CSF_PANEL_COUNT_SUF", hint)
        self.assertNotIn(" 99 ", hint)
        self.assertNotIn(" 48 ", hint)

    def test_unreadable_stats_show_unknown(self):
        self.refresh_with(
            '{{Civ="CIV_TEST",Mode="slot",Name="Test",CanReceiveInfluence=true}}',
            "nil",
        )
        hint = self.evaluate("Controls.CSFHint.text")
        self.assertIn(
            "LOC_CSF_PANEL_COUNT_MID LOC_CSF_PANEL_COUNT_UNKNOWN LOC_CSF_PANEL_COUNT_SUF",
            hint,
        )

    def test_legacy_record_reason_has_dedicated_text(self):
        self.assertEqual(
            self.evaluate('CSF_ReasonText("founding_legacy_record_unconfirmed")'),
            "LOC_CSF_REASON_LEGACY_RECORD",
        )
        stale = self.evaluate('CSF_ReasonText("founding_city_missing")')
        self.assertNotEqual(stale, "LOC_CSF_REASON_LEGACY_RECORD")

    def test_panel_texts_no_longer_ask_to_raise_starting_count(self):
        text = TEXT.read_text(encoding="utf-8")
        self.assertNotIn("调高", text)
        self.assertNotIn("raise the City-State count", text)
        self.assertIn("候选可重复建立", text)
        self.assertIn("same candidate can be founded again", text)
        self.assertIn("LOC_CSF_REASON_LEGACY_RECORD", text)
        self.assertIn("LOC_CSF_PANEL_COUNT_UNKNOWN", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
