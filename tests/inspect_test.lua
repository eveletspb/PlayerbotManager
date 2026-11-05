local frames={}
function CreateFrame()
    local frame={scripts={}}
    function frame:SetScript(key,value) self.scripts[key]=value end
    function frame:RegisterEvent() end
    frames[#frames+1]=frame
    return frame
end
local inspected='A'
function UnitName(unit) return unit=='player' and 'Owner' or inspected end
function UnitGUID(unit) return UnitName(unit) end
function UnitIsUnit(a,b) return UnitName(a)==UnitName(b) end
function UnitExists() return true end
function GetTime() return 100 end
function ClearInspectPlayer() end
function LichborneOutput() end
function GetActiveTalentGroup() return 1 end
function GetNumTalents() return 0 end
local inspectFlag
function GetTalentTabInfo(tab,inspect)
    inspectFlag=inspect
    return 'Tree',nil,(tab==(inspect and 3 or 2) and 71 or 0)
end
function GetInventoryItemLink(_,slot) return 'item:'..slot end
function GetItemInfo(link) return 'Item',link,4,200,nil,nil,nil,nil,'INVTYPE_HEAD' end
PBM={State={rowFrames={},classScroll={}},DBG=function() end,RefreshRows=function() end,
    CalculateUnitGearScore=function() return 4000 end,GetItemQualityColor=function() end}
dofile('PBM/PBM_Constants.lua')
dofile('PBM/PBM_Database.lua')
dofile('PBM/PBM_Inspect.lua')
dofile('PBM/PBM_Spec.lua')
local gear,spec=frames[1],frames[2]
local function rows()
    LichborneTrackerDB.rows={{name='Before',cls='Mage'},{name='A',cls='Mage',spec='Fire'},
        {name='B',cls='Mage',spec='Arcane'},{name='Owner',cls='Mage',spec='Arcane'}}
    PBM.State.LichborneInspectUnit='party1'; inspected='A'
end
rows()
PBM.State.LichborneSpecTarget=2; PBM.State.LichborneSpecGUID='A'
PBM.RemoveCharacterReferences('Before')
spec.scripts.OnUpdate(spec,3)
assert(LichborneTrackerDB.rows[1].name=='A' and LichborneTrackerDB.rows[1].spec=='Frost')
assert(LichborneTrackerDB.rows[2].name=='B' and LichborneTrackerDB.rows[2].spec=='Arcane')
rows()
PBM.State.LichborneInspectTarget=2; PBM.State.LichborneInspectGUID='A'
PBM.RemoveCharacterReferences('Before')
gear.scripts.OnUpdate(gear,3)
assert(LichborneTrackerDB.rows[1].gs==200 and LichborneTrackerDB.rows[2].gs==nil)
-- Removing the inspected character must abort instead of filling the following row.
for _, mode in ipairs({'LichborneInspectTarget','LichborneSpecTarget'}) do
    rows(); PBM.State[mode]=2
    PBM.RemoveCharacterReferences('A')
    local frame=mode=='LichborneInspectTarget' and gear or spec
    frame.scripts.OnUpdate(frame,3)
    assert(PBM.State[mode]==nil and LichborneTrackerDB.rows[2].name=='B')
    assert(LichborneTrackerDB.rows[2].gs==nil and LichborneTrackerDB.rows[2].spec=='Arcane')
end
-- A changed unit or unrelated inspect event cannot overwrite A.
rows(); PBM.State.LichborneSpecTarget=2
spec.scripts.OnEvent(spec,'INSPECT_READY','Other')
assert(PBM.State.LichborneSpecTarget==2 and LichborneTrackerDB.rows[2].spec=='Fire')
inspected='B'; spec.scripts.OnUpdate(spec,3)
assert(PBM.State.LichborneSpecTarget==nil and LichborneTrackerDB.rows[3].spec=='Arcane')
-- Self talents must bypass the remote inspect cache.
rows(); PBM.State.LichborneInspectUnit='player'; PBM.State.LichborneSpecGUID='Owner'
PBM.State.LichborneSpecTarget=4
spec.scripts.OnUpdate(spec,3)
assert(inspectFlag==false and LichborneTrackerDB.rows[4].spec=='Fire')
-- Bridge specialization callbacks must also resolve the name after a roster edit.
local file=assert(io.open('PBM/PBM_TrackerCore.lua')); local source=file:read('*a'); file:close()
local first=assert(source:find('    local function ApplyBridgeSpec',1,true))
local last=assert(source:find('    local addGroupBtn',first,true))
local apply=assert(loadstring(source:sub(first,last-1)..' return ApplyBridgeSpec'))()
rows(); PBM.RemoveCharacterReferences('Before')
assert(apply('A',0,71,0) and LichborneTrackerDB.rows[1].spec=='Fire')
assert(LichborneTrackerDB.rows[2].spec=='Arcane')
PBM.RemoveCharacterReferences('A')
assert(not apply('A',0,0,71) and LichborneTrackerDB.rows[1].spec=='Arcane')
print('PASS inspect: shifted/deleted rows, changed units, mismatched replies and self talents')
