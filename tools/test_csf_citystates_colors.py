"""Offline integration: real CSF adapter, private official-style cache, no debug API."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

SRC = Path(__file__).resolve().parents[1] / 'src' / 'UI'


class CityStatesColors(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().SRC = str(SRC).replace('\\', '/')
        self.lua.execute('''
            debug=nil; W={includes=0,props={}}; NativeUI={}
            local api={GetPlayerColors=function(id) if id==0 then return 10,20 end end,
                GetPlayerColorValues=function(civ) if civ=='CIV_TEST' then return 30,40 end end,
                PlaySound=function(name) W.sound=name end}
            setmetatable(NativeUI,{__index=api,__newindex=function()error('read only')end})
            UI=NativeUI
            Game={GetProperty=function(_,k)return W.props[k]end}
            PlayerConfigurations=setmetatable({}, {__index=function(_,id)
                return {GetCivilizationTypeName=function()return id==23 and 'CIV_TEST' or 'OTHER'end}
            end})
            Locale={Lookup=function(s)return s end}
            function include(name)
                if name=='CityStates_Expansion2' then
                    W.includes=W.includes+1
                    InstanceManager={GetInstance=function(self)return W.row end}
                    Teams={[0]={0,1}}
                    PlayerManager={GetAliveIDs=function()return {0,1,23,24}end}
                    local entries={}
                    function GetData()
                        local a,b=UI.GetPlayerColors(23)
                        entries[23]={iPlayer=23,Name='Test',ColorPrimary=a,ColorSecondary=b}
                    end
                    function AddCityStateRow(e) assert(e.ColorPrimary and e.ColorSecondary);return e end
                    function GetRelationshipPipAtlasPieces(e)return e.Name,'atlas',42 end
                    function view_private()
                        GetData();local e=entries[23];AddCityStateRow(e)
                        return GetRelationshipPipAtlasPieces(e)
                    end
                else dofile(SRC..'/'..name..'.lua') end
            end
            dofile(SRC..'/CSF_CityStatesPatch.lua')
        ''')

    def test_private_cache_has_colors_without_debug(self):
        self.assertEqual(self.lua.eval('view_private()'), ('Test', 'atlas', 42))
        self.assertEqual(self.lua.eval('UI.GetPlayerColors(23)'), (30, 40))

    def test_engine_object_and_existing_players_are_preserved(self):
        self.assertIsNone(self.lua.eval('NativeUI.GetPlayerColors(23)'))
        self.assertEqual(self.lua.eval('UI.GetPlayerColors(0)'), (10, 20))
        self.lua.execute("UI.PlaySound('native')")
        self.assertEqual(self.lua.eval('W.sound'), 'native')

    def test_safe_fallback_and_no_recursive_proxy(self):
        a, b = self.lua.eval('UI.GetPlayerColors(61)')
        self.assertIsInstance(a, (int, float))
        self.assertIsInstance(b, (int, float))

    def test_copy_suffix_is_idempotent(self):
        self.lua.execute("W.props.CSF_CopySuffix_23=' II'")
        self.assertEqual(self.lua.eval('view_private()')[0], 'Test II')
        self.assertEqual(self.lua.eval('view_private()')[0], 'Test II')

    def test_duplicate_include_does_not_rewrap_native_api(self):
        self.lua.execute("dofile(SRC..'/CSF_CityStatesPatch.lua')")
        self.assertEqual(self.lua.eval('W.includes'), 1)
        self.assertEqual(self.lua.eval('UI.GetPlayerColors(23)'), (30, 40))

    def install_quest_row(self, bcs=True):
        self.lua.execute('''
            function control()
                return {SetHide=function(s,v)s.hidden=v end,
                    SetText=function(s,v)s.text=v end,
                    SetToolTipString=function(s,v)s.tooltip=v end}
            end
            W.row={}; W.manager={m_InstanceName='CityStateRowInstance'}
            setmetatable(W.manager,{__index=InstanceManager})
        ''')
        if bcs:
            self.lua.execute('W.row.CuiCityStateQuest=control(); W.row.CuiQuestGrid=control()')
        else:
            self.lua.execute('W.row.QuestIcon=control(); W.nativeQuest=W.row.QuestIcon')

    def test_bcs_layout_official_quest_calls_fill_real_label(self):
        self.install_quest_row()
        self.lua.execute('''
            local row=W.manager:GetInstance()
            row.QuestIcon:SetHide(false)
            row.QuestIcon:SetToolTipString('Quests[NEWLINE]Build a campus')
        ''')
        self.assertEqual(self.lua.eval('W.row.CuiCityStateQuest.text'),
                         'Quests[NEWLINE]Build a campus')
        self.assertFalse(self.lua.eval('W.row.CuiQuestGrid.hidden'))

    def test_recycled_bcs_row_without_quest_clears_placeholder_and_old_text(self):
        self.install_quest_row()
        self.lua.execute('''
            local row=W.manager:GetInstance()
            row.QuestIcon:SetHide(false); row.QuestIcon:SetToolTipString('old quest')
            row=W.manager:GetInstance()
            row.QuestIcon:SetHide(true); row.QuestIcon:SetToolTipString('Quests')
        ''')
        self.assertTrue(self.lua.eval('W.row.CuiQuestGrid.hidden'))
        self.assertEqual(self.lua.eval('W.row.CuiCityStateQuest.text'), '')

    def test_native_quest_icon_is_never_replaced(self):
        self.install_quest_row(False)
        self.lua.execute('W.manager:GetInstance()')
        self.assertTrue(self.lua.eval('W.row.QuestIcon==W.nativeQuest'))

    def test_other_instance_names_are_not_adapted(self):
        self.install_quest_row()
        self.lua.execute("W.manager.m_InstanceName='Other'; W.manager:GetInstance()")
        self.assertTrue(self.lua.eval('W.row.QuestIcon==nil'))

    def install_team_configs(self):
        self.lua.execute('''
            W.teams={[0]=0,[1]=0,[23]=23,[24]=24}
            PlayerConfigurations=setmetatable({}, {__index=function(_,id)
                return {GetTeam=function()return W.teams[id]end}
            end})
        ''')

    def test_new_native_team_has_real_member_without_snapshot_mutation(self):
        self.install_team_configs()
        self.assertEqual(self.lua.eval('#Teams[23]'), 1)
        self.assertEqual(self.lua.eval('Teams[23][1]'), 23)
        self.assertEqual(self.lua.eval('#Teams[0]'), 2)
        self.assertEqual(self.lua.eval('#Teams[99]'), 0)

    def test_unassigned_minors_do_not_become_a_fake_team(self):
        self.install_team_configs()
        self.lua.execute('W.teams[23]=-1; W.teams[24]=-1')
        self.assertEqual(self.lua.eval('#Teams[-1]'), 0)

    def test_missing_team_cache_reflects_current_config_each_time(self):
        self.install_team_configs()
        self.assertEqual(self.lua.eval('#Teams[23]'), 1)
        self.lua.execute('W.teams[24]=23')
        self.assertEqual(self.lua.eval('#Teams[23]'), 2)

    def install_identity_mirrors(self):
        self.lua.execute('''
            W.writes=0; W.configs={}; W.identities={{PlayerID=23,Civ='CIV_TEST',Leader='LEADER_TEST'}}
            CivilizationLevelTypes={CIVILIZATION_LEVEL_CITY_STATE=123}
            SlotStatus={SS_COMPUTER=1}
            function make_config()
                return {level=0,status=2,values={},
                    GetCivilizationTypeName=function(s)return s.civ end,
                    GetLeaderTypeName=function(s)return s.leader end,
                    GetCivilizationLevelTypeID=function(s)return s.level end,
                    GetSlotStatus=function(s)return s.status end,
                    GetValue=function(s,k)return s.values[k]end,
                    GetCivilizationShortDescription=function(s)return s.values.CIVILIZATION_SHORT_DESCRIPTION end,
                    GetCivilizationDescription=function(s)return s.values.CIVILIZATION_DESCRIPTION end,
                    GetLeaderName=function(s)return s.name end,
                    SetLeaderName=function(s,v)W.writes=W.writes+1;if not W.silent_names then s.name=v end end,
                    SetLeaderTypeName=function(s,v)W.writes=W.writes+1;if not W.silent then s.leader=v end end,
                    SetCivilizationTypeName=function(s,v)W.writes=W.writes+1;if not W.silent then s.civ=v end end,
                    SetValue=function(s,k,v)
                        W.writes=W.writes+1
                        if not W.silent then
                            if k=='CIVILIZATION_LEVEL_TYPE_ID' then s.level=v end
                            if not W.silent_names then s.values[k]=v end
                        end
                    end,
                    SetSlotStatus=function(s,v)W.writes=W.writes+1;if not W.silent then s.status=v end end}
            end
            PlayerConfigurations=setmetatable({}, {__index=function(_,id)
                W.configs[id]=W.configs[id] or make_config(); return W.configs[id]
            end})
            ExposedMembers={CSF={GetFoundedIdentities=function()return W.identities end}}
        ''')

    def test_closed_identity_mirror_uses_real_setters_and_is_idempotent(self):
        self.install_identity_mirrors()
        self.assertTrue(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertEqual(self.lua.eval('W.configs[23].civ'), 'CIV_TEST')
        self.assertEqual(self.lua.eval('W.configs[23].level'), 123)
        self.assertEqual(self.lua.eval('W.configs[23].status'), 1)
        self.assertIsNone(self.lua.eval('W.configs[0]'))
        count = self.lua.eval('W.writes')
        self.assertTrue(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertEqual(self.lua.eval('W.writes'), count)

    def test_silent_configuration_write_is_not_success(self):
        self.install_identity_mirrors()
        self.lua.execute('W.silent=true')
        self.assertFalse(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertIsNone(self.lua.eval('W.configs[23].civ'))

    def test_published_isolated_identity_uses_real_frontend_configuration(self):
        self.install_identity_mirrors()
        self.lua.execute('''
            ExposedMembers.CSF.GetPublishedIdentities=function()return W.identities end
            ExposedMembers.CSF.GetFoundedIdentities=function()error('must include published isolated players')end
            W.identities[1].Isolated=true
            W.identities[1].ShortName='LOC_ISOLATED'
            W.identities[1].Description='LOC_ISOLATED_DESCRIPTION'
        ''')
        self.assertTrue(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertEqual(self.lua.eval('W.configs[23]:GetCivilizationShortDescription()'), 'LOC_ISOLATED')
        self.assertEqual(self.lua.eval('W.configs[23].level'), 123)

    def test_native_names_restore_and_second_sync_does_not_rewrite(self):
        self.install_identity_mirrors()
        self.lua.execute("W.identities[1].ShortName='LOC_NAME'; W.identities[1].Description='LOC_DESCRIPTION'; W.identities[1].Adjective='LOC_ADJECTIVE'")
        self.assertTrue(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertEqual(self.lua.eval('W.configs[23]:GetCivilizationShortDescription()'), 'LOC_NAME')
        self.assertEqual(self.lua.eval('W.configs[23]:GetLeaderName()'), 'LOC_NAME')
        count = self.lua.eval('W.writes')
        self.assertTrue(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertEqual(self.lua.eval('W.writes'), count)

    def test_silent_name_write_fails_readback(self):
        self.install_identity_mirrors()
        self.lua.execute("W.identities[1].ShortName='LOC_NAME'; W.identities[1].Description='LOC_DESCRIPTION'; W.silent_names=true")
        self.assertFalse(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))

    def test_reserved_slot_or_malformed_authority_is_rejected(self):
        self.install_identity_mirrors()
        self.lua.execute('W.identities[1].PlayerID=62')
        self.assertFalse(self.lua.eval('CSF_SynchronizeFoundedIdentities()'))
        self.assertEqual(self.lua.eval('W.writes'), 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
