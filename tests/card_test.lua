local frames, sent, messages = {}, {}, {}
function CreateFrame()
    local f={scripts={},events={},shown=true}
    function f:SetScript(key,value) self.scripts[key]=value end
    function f:RegisterEvent(event) self.events[event]=true end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    frames[#frames+1]=f
    return f
end
function GetTime() return 100 end
function UnitName() return 'Owner' end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function SendAddonMessage(_,payload) sent[#sent+1]=payload end
function ChatFrame_AddMessageEventFilter() end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) messages[#messages+1]=message end}
dofile('PBM/PBM_Constants.lua')
dofile('PBM/PBM_Database.lua')
dofile('PBM/PBM_Bridge.lua')
dofile('PBM/PBM_Core.lua')
PBM.SendToBot=function() end
PBM.RefreshRows=function() end
local file=assert(io.open('PBM/PBM_CharSheet.lua')); local sheet=file:read('*a'); file:close()
local first=assert(sheet:find('        mb:SetScript("OnClick", function()',1,true))
local last=assert(sheet:find('\n    end\n    menu.talentsMenu',first,true))
local templateClick
local mb={SetScript=function(_,_,callback) templateClick=callback end}
local row={name='Bot',cls='Mage',spec='Fire'}
local other={name='Other',cls='Mage',spec='Arcane'}
LichborneTrackerDB.rows={row,other}
local card={botName='Bot',sourceRow={dbIndex=2},IsShown=function() return true end}
local icon={SetTexture=function(self,value) self.texture=value end,texture='old-icon'}
card.specBtn={icon=icon}
PBM.State.lastQueriedMenu.Bot=card
local dropdown={Hide=function() end}
local def={spec='frost',wowSpec='Frost',icon='new-icon'}
assert(loadstring('return function(mb,menu,def,specTex,talentsMenu)\n'..sheet:sub(first,last-1)..'\nend'))()(mb,card,def,icon,dropdown)
local function receive(op,payload) PBM.HandleBridgeAddonMessage('MBOT',op..'~'..payload,'Owner') end
local function listReply()
    local token=sent[#sent]:match('([^~]+)$')
    receive('TALENT_SPEC_BEGIN','Bot~'..token)
    receive('TALENT_SPEC_ITEM','Bot~'..token..'~2~frost~0-71-0')
    receive('TALENT_SPEC_END','Bot~'..token)
    return assert(sent[#sent]:match('TALENT_SPEC_APPLY~([^~]+)'))
end
PBM.Bridge.state='available'
PBM.Bridge.capabilities.TALENT_SPEC_APPLY_V1=true
templateClick()
assert(sent[#sent]:find('TALENT_SPEC_LIST~Bot~',1,true))
assert(row.spec=='Fire' and other.spec=='Arcane' and icon.texture=='old-icon')
local token=listReply()
receive('TALENT_SPEC_APPLY_RESULT',token..'~Bot~ERR~RATE_LIMIT~1~2~71~0~0')
assert(row.spec=='Fire' and other.spec=='Arcane' and icon.texture=='old-icon')
-- The acknowledgement resolves the character by name after a row reorder.
templateClick(); token=listReply()
LichborneTrackerDB.rows={other,row}
local queried
local query=PBM.QueryBotStrategies
PBM.QueryBotStrategies=function(name) queried=name end
receive('TALENT_SPEC_APPLY_RESULT',token..'~Bot~OK~OK~1~2~0~71~0')
assert(row.spec=='Frost' and other.spec=='Arcane' and queried=='Bot')
assert(icon.texture==PBM.SPEC_ICONS.Frost)
-- A closed/reused card still updates Bot's record, never the replacement's icon.
row.spec='Fire'; card.botName='Other'; icon.texture='other-icon'
PBM.ApplyTalentTemplate('Bot','frost','Frost'); token=listReply()
receive('TALENT_SPEC_APPLY_RESULT',token..'~Bot~OK~OK~1~2~0~71~0')
assert(row.spec=='Frost' and other.spec=='Arcane' and icon.texture=='other-icon')
-- Timeout cannot turn an unconfirmed template into a saved spec.
row.spec='Fire'
PBM.ApplyTalentTemplate('Bot','frost','Frost'); listReply()
for _,frame in ipairs(frames) do
    if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame,6) end
end
assert(row.spec=='Fire')
-- Legacy applies only after the bot's Picking reply, including with the card closed.
PBM.Bridge.state='unavailable'
PBM.ApplyTalentTemplate('Bot','frost','Frost')
for _,frame in ipairs(frames) do
    if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame,0.4) end
end
assert(row.spec=='Fire')
local core
for _,frame in ipairs(frames) do if frame.events.CHAT_MSG_WHISPER then core=frame end end
core.scripts.OnEvent(core,'CHAT_MSG_WHISPER','Picking frost','Bot')
assert(row.spec=='Frost' and other.spec=='Arcane' and PBM.State.pickingPending.Bot==nil)
PBM.QueryBotStrategies=query
print('PASS card: confirmed template writes, row identity, rejected/time-out applies and legacy confirmation')
