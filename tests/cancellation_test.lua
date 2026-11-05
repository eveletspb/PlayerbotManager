local frames, sent, buttons = {}, {}, {}
function CreateFrame()
    local f={scripts={}}
    function f:SetScript(key,fn) self.scripts[key]=fn end
    function f:SetBackdropColor() end
    frames[#frames+1]=f
    return f
end
function SendChatMessage(msg) sent[#sent+1]=msg end
PBM={State={},CLASS_COLORS={}}
dofile('PBM/PBM_Throttle.lua')
local throttle=frames[1]
local originalSend=SendChatMessage
SendChatMessage('player guild chat','GUILD')
assert(#sent==1 and PBM.GetQueueSize()==0 and SendChatMessage==originalSend)
PBM.SendChatMessage('PBM command','SAY'); PBM.ClearQueue()
throttle.scripts.OnUpdate(throttle,1)
assert(#sent==1)
PBM.SendChatMessage('sale','WHISPER',nil,'Bot')
PBM.AfterChatQueue(function() assert(sent[#sent]=='sale'); SendChatMessage('inventory refresh') end)
throttle.scripts.OnUpdate(throttle,1)
assert(sent[#sent]=='inventory refresh')

local function read(path)
    local file=assert(io.open(path)); local source=file:read('*a'); file:close(); return source
end
local function section(source,first,last)
    local start=assert(source:find(first,1,true)); local finish=assert(source:find(last,start+#first,true))
    return source:sub(start,finish-1)
end
function LichborneOutput() end
function LeaveParty() end
function UnitName(unit) return unit=='player' and 'Owner' or 'Bot' end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 1 end
function GetTime() return 100 end
PBM.SetInviteActive=function() end
PBM.UpdateInviteButtons=function() end
LichborneAddStatus={SetText=function() end}
local raid=read('PBM/PBM_Raid.lua')
QueueBotAdds=assert(loadstring(section(raid,'    local function QueueBotAdds','    local inviteBtn')..'\nreturn QueueBotAdds'))()
stopInviteBtn=CreateFrame()
assert(loadstring(section(raid,'    stopInviteBtn:SetScript("OnClick"','    stopInviteBtn:Hide()')))()
local roster={}
for i=1,39 do roster[i]={name='Bot'..i} end
PBM.GetCurrentRoster=function() return roster,39 end
LichborneTrackerDB={raidRosters={['N/A (5-Man)_A']=roster},raidGroup='A'}
for _, name in ipairs({'inviteBtn','inviteGroupBtn'}) do
    _G[name]=CreateFrame()
    local ending=name=='inviteBtn' and '    inviteStaticAfterLoad' or '    _G["LichborneInviteGroupBtn"]'
    assert(loadstring(section(raid,'    '..name..':SetScript("OnClick",function()',ending)))()
    _G[name].scripts.OnClick()
    local active=PBM.State.activeInviteFrame
    active.scripts.OnUpdate(active,1.5)
    active.scripts.OnUpdate(active,1)
    active.scripts.OnUpdate(active,0.1)
    assert(PBM.GetQueueSize()>1)
    PBM.SendChatMessage('unrelated PBM command','SAY')
    local before=#sent
    stopInviteBtn.scripts.OnClick()
    for _=1,10 do throttle.scripts.OnUpdate(throttle,1) end
    assert(#sent==before+1 and sent[#sent]=='unrelated PBM command')
end
-- Successful operations still deliver their queued final command after normal completion.
local operation=CreateFrame()
PBM.SendChatMessage('final invite','SAY',nil,nil,function() return not operation.cancelled end)
PBM.State.activeInviteFrame=nil
throttle.scripts.OnUpdate(throttle,1)
assert(sent[#sent]=='final invite')

-- Run the actual full-scan and Stop callbacks, skipping their surrounding UI layout.
function MakeSimpleBtn(name) local f=CreateFrame(); buttons[name]=f; return f end
MakeTrackerBtn=MakeSimpleBtn
function UnitExists() return true end
function UnitIsPlayer() return true end
function UnitIsUnit(unit,other) return unit==other end
function UnitGUID(unit) return unit end
function CheckInteractDistance() return true end
local inspectCalls, applied=0,0
function InspectUnit() inspectCalls=inspectCalls+1 end
PBM.DBG=function() end
PBM.RefreshRows=function() end
PBM.BridgeHasCapability=function() return true end
PBM.ApplyBridgeGear=function() applied=applied+1; return true end
local gearReply, gearTimeout, specReply, specTimeout
PBM.BridgeRequestGear=function(_,reply,timeout) gearReply,gearTimeout=reply,timeout; return true end
PBM.BridgeRequestDetail=function(_,reply,timeout) specReply,specTimeout=reply,timeout; return true end
LichborneTrackerDB.rows={{name='Owner',cls='Mage'},{name='Bot',cls='Mage'}}
local tracker=read('PBM/PBM_TrackerCore.lua')
-- A successful zero-score response must not trigger the single-target legacy fallback.
function UnitClass() return 'Mage','MAGE' end
PBM.CLASS_TOKEN_MAP={MAGE='Mage'}
gsBtn=CreateFrame()
local targetGear=section(tracker,'    gsBtn:SetScript("OnClick"','    -- ── Update Target Spec')
assert(loadstring('local SetScanActive=function() end\n'..targetGear))()
gsBtn.scripts.OnClick()
local before=inspectCalls
gearReply({score=0,realGs=0})
assert(applied==1 and inspectCalls==before)
applied=0
local stop=section(tracker,'    local stopInspectBtn =','    -- Row y=10:')
local scan=section(tracker,'    local maintBtn =','    local loginBtn')
local factory=assert(loadstring('return function() local activeInspectFrame\n'..
    'local SetScanActive=function() end\nlocal AddGroupMembers=function(done) done(0,0) end\n'..
    'local ApplyBridgeSpec=function() error("cancelled spec applied") end\n'..stop..scan..'\nreturn maintBtn, stopInspectBtn end'))()
local startScan,stopScan=factory()
local function beginGear()
    startScan.scripts.OnClick()
    local frame=frames[#frames]
    frame.scripts.OnUpdate(frame,0.1) -- player inspect
    PBM.State.LichborneInspectTarget=nil
    frame.scripts.OnUpdate(frame,0.1) -- bot bridge read
    return frame
end
local gearFrame=beginGear()
stopScan.scripts.OnClick()
before=inspectCalls
gearReply({realGs=4000}); gearTimeout()
assert(applied==0 and inspectCalls==before and PBM.State.LichborneInspectTarget==nil)
-- An old scan cannot modify the replacement scan either.
beginGear()
local oldReply,oldTimeout=gearReply,gearTimeout
beginGear(); before=inspectCalls
oldReply({realGs=4000}); oldTimeout()
assert(applied==0 and inspectCalls==before)
-- Advance a current scan into the specialization phase, then stop its pending read.
gearFrame=beginGear()
before=inspectCalls
gearReply({score=0,realGs=0})
assert(applied==1 and inspectCalls==before)
gearFrame.scripts.OnUpdate(gearFrame,0.1)
local specFrame=frames[#frames]
specFrame.scripts.OnUpdate(specFrame,0.1)
PBM.State.LichborneSpecTarget=nil
specFrame.scripts.OnUpdate(specFrame,0.1)
assert(specReply)
stopScan.scripts.OnClick(); before=inspectCalls
specReply('Bot','Human','Male','Mage',80,0,0,71); specTimeout()
assert(inspectCalls==before and PBM.State.LichborneSpecTarget==nil)
print('PASS cancellation: global chat isolation, raid/group Stop queues, late and superseded scan callbacks')
