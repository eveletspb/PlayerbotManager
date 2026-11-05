local sent, notices={},{}
local raid,party,target=0,0,nil
function GetNumRaidMembers() return raid end
function GetNumPartyMembers() return party end
function UnitName(unit)
    if unit=='target' then return target end
    if unit=='player' then return 'Owner' end
    if unit=='raid1' or unit=='party1' then return 'Bot' end
end
function UnitIsPlayer() return true end
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) notices[#notices+1]=message end}
PBM={SendChatMessage=function(message,channel,_,recipient)
    assert(message,'nil chat message')
    sent[#sent+1]={message=message,channel=channel,recipient=recipient}
end}
dofile('PBM/PBM_Engine.lua')
dofile('PBM/PBM_Commands.lua')
local function checkSend(action,channel,recipient)
    local before=#sent
    action('selfbot on')
    assert(#sent==before+1 and sent[#sent].message=='selfbot on')
    assert(sent[#sent].channel==channel and sent[#sent].recipient==recipient)
end
local groupActions={PBM.SendToGroup,PBM.ActionToGroup,PBM.ActionToTargetOrGroup}
-- Exercise the shipped local tab helpers without creating their surrounding layout.
for _,path in ipairs({'PBM/PBM_TopTabs.lua','PBM/PBM_BottomTabs.lua'}) do
    local file=assert(io.open(path)); local source=file:read('*a'); file:close()
    local first=assert(source:find('local function ActionToGroup',1,true))
    local last=assert(source:find('\n-- ===',first,true))
    local group,targetOrGroup=assert(loadstring(source:sub(first,last-1)..
        '\nreturn ActionToGroup,ActionToTargetOrGroup'))()
    groupActions[#groupActions+1]=group
    groupActions[#groupActions+1]=targetOrGroup
end
for _,size in ipairs({1,3,5,6,40}) do
    raid=size; party=0; target=nil
    for _,action in ipairs(groupActions) do checkSend(action,'RAID') end
    assert(PBM.ActionToGroup('stats on')==true)
    assert(PBM.isMember('Bot') and PBM.toUnit('Bot')=='raid1')
end
raid=0; party=1
for _,action in ipairs(groupActions) do checkSend(action,'PARTY') end
assert(PBM.isMember('Bot') and PBM.toUnit('Bot')=='party1')
target='Target'
checkSend(PBM.ActionToTargetOrGroup,'WHISPER','Target')
raid=0; party=0; target=nil
local before=#sent
assert(PBM.ActionToGroup('stats on')==false)
assert(PBM.ActionToTargetOrGroup('reset')==false)
assert(#sent==before and #notices==2)
assert(not PBM.isMember('Bot') and PBM.toUnit('Bot')==nil)
assert(PBM.isMember('Owner') and PBM.toUnit('Owner')=='player')
print('PASS group: small/full raid and party routing, target priority, membership and solo feedback')
