local frames, sent, chat = {}, {}, {}
function CreateFrame()
    local f = {scripts={}, events={}, shown=true}
    function f:RegisterEvent(event) self.events[event]=true end
    function f:SetScript(key, fn) self.scripts[key]=fn end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    frames[#frames+1]=f
    return f
end
function GetTime() return 100 end
function UnitName() return 'Owner' end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function SendAddonMessage(_, payload) sent[#sent+1]=payload end
function ChatFrame_AddMessageEventFilter() end
function SendChatMessage() end
PBM = {SendChatMessage=SendChatMessage}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = {AddMessage=function() end}
dofile('PBM/PBM_Constants.lua')
dofile('PBM/PBM_Bridge.lua')
dofile('PBM/PBM_Core.lua')
PBM.RequestLegacyInventory = function() end
PBM.SendToBot = function(msg, name) chat[#chat+1]={msg=msg, name=name} end
PBM.AfterChatQueue = function(callback) callback() end
local core
for _, frame in ipairs(frames) do if frame.events.CHAT_MSG_ADDON then core=frame end end
local function receive(op, payload, sender)
    core.scripts.OnEvent(core, 'CHAT_MSG_ADDON', 'MBOT', op..(payload and '~'..payload or ''), 'WHISPER', sender or 'Owner')
end
local function tokenFor(request)
    for i=#sent,1,-1 do
        if sent[i]:find('GET~'..request..'~',1,true) then return sent[i]:match('([^~]+)$') end
    end
end
local function state(bot, token, strategy)
    receive('STATE_BEGIN',token..'~'..bot..'~1~0')
    receive('STATE_ITEM',token..'~'..bot..'~C~1~'..(strategy or 'fire'))
    receive('STATE_END',token..'~'..bot..'~1~0')
end
PBM.BridgeProbe()
receive('HELLO_ACK','1~Fake','Other')
receive('CAPS','INVENTORY_V1','Other')
receive('CAPS_END',nil,'Other')
assert(not PBM.BridgeIsAvailable())
receive('HELLO_ACK','1~Bridge')
receive('CAPS','GEAR_ITEM_LINK_V1,GEAR_INSPECT_V1,STATE_FRAMING_V1,DETAIL_V1,STATS_V1,INVENTORY_V1,TALENT_SPEC_APPLY_V1')
receive('CAPS_END')
assert(PBM.BridgeIsAvailable())

local gear
local _, token = PBM.BridgeRequestGear('Bot',function(value) gear=value end)
receive('GEAR_BEGIN','Bot~'..token)
receive('GEAR_SUMMARY','Bot~'..token..'~200~4000')
for slot=0,18 do
    if slot ~= 3 then
        receive('GEAR_ITEM','Bot~'..token..'~'..slot..'~'..(1000+slot)..'~200~4')
        receive('GEAR_LINK','Bot~'..token..'~'..slot..'~item:'..(1000+slot)..':0:0:0:0:0:0:0')
    end
end
receive('GEAR_END','Bot~'..token)
local expected={0,1,2,14,4,8,9,5,6,7,10,11,12,13,15,16,17}
for column, slot in ipairs(expected) do assert(gear.ilvlLink[column]:match('item:(%d+)') == tostring(1000+slot)) end
-- A complete empty snapshot is authoritative and must clear previous scores everywhere.
local row={name='Bot',cls='Mage',gs=200,realGs=4000}
local rosterSlot={name='Bot',gs=200,realGs=4000}
LichborneTrackerDB={rows={row},raidRosters={raid={rosterSlot}}}
PBM.FindTrackedRowIndexByName=function() return 1 end
local applied,reason
local function applyGear(value,err)
    reason=err
    applied=PBM.ApplyBridgeGear('Bot',value)
end
_,token=PBM.BridgeRequestGear('Bot',applyGear)
receive('GEAR_BEGIN','Bot~'..token)
receive('GEAR_SUMMARY','Bot~'..token..'~0~0')
receive('GEAR_END','Bot~'..token)
assert(applied and row.gs==0 and row.realGs==0 and rosterSlot.gs==0 and rosterSlot.realGs==0)
for slot=1,PBM.GEAR_SLOTS do assert(row.ilvl[slot]==0 and row.ilvlLink[slot]=='') end
-- Incomplete/malformed/error responses must not erase the previous valid snapshot.
row.gs=200; row.realGs=4000
for _,summary in ipairs({'', '~invalid~0', '~-1~0'}) do
    _,token=PBM.BridgeRequestGear('Bot',applyGear)
    receive('GEAR_BEGIN','Bot~'..token)
    if summary~='' then receive('GEAR_SUMMARY','Bot~'..token..summary) end
    receive('GEAR_END','Bot~'..token)
    assert(not applied and reason=='INVALID_GEAR_SUMMARY' and row.gs==200 and row.realGs==4000)
end
_,token=PBM.BridgeRequestGear('Bot',applyGear)
receive('GEAR_BEGIN','Bot~'..token)
receive('GEAR_ERROR','Bot~'..token..'~FORBIDDEN')
receive('GEAR_END','Bot~'..token)
assert(not applied and reason=='FORBIDDEN' and row.gs==200 and row.realGs==4000)

for _, request in ipairs({'DETAIL','STATS'}) do
    local name='unexpected'
    local callback=function(value) name=value end
    local fn=request=='DETAIL' and PBM.BridgeRequestDetail or PBM.BridgeRequestStats
    local _, t=fn('Bot',callback)
    receive(request..'_RESULT',t..'~')
    assert(name==nil, request..' must reject an empty result')
end
local before=#sent
PBM.BridgeRequestInventory('Бот')
assert(sent[#sent]:find('GET~INVENTORY~Бот~',1,true))
PBM.BridgeRequestDetail('Бот',function() end)
assert(sent[#sent]:find('GET~DETAIL~Бот~',1,true))
PBM.BridgeRequestTalentSpecs('Бот',function() end)
assert(sent[#sent]:find('GET~TALENT_SPEC_LIST~Бот~',1,true))
assert(#sent==before+3)

local applied={}
local menu={botName='Bot', IsShown=function() return true end,
    applyBridgeStats=function() applied.stats=true end,
    applyBridgeDetail=function() applied.detail=true end}
PBM.UpdateStrategyToggles=function() end
sent={}
PBM.QueryBotStrategies('Bot',menu,true)
state('Bot',tokenFor('STATE'))
assert(tokenFor('STATS') and not tokenFor('DETAIL'))
local pending=PBM.State.strategyPending.Bot
receive('STATS_RESULT',tokenFor('STATS')..'~Bot~80~1~2~3~4~20~100~0~100')
assert(applied.stats and not applied.detail and PBM.State.strategyPending.Bot==pending)
receive('DETAIL_RESULT',tokenFor('DETAIL')..'~Bot~Human~Male~Mage~80~0~0~71~200')
assert(applied.detail and pending.step==5 and chat[#chat].msg=='ss ?')
core.scripts.OnEvent(core,'CHAT_MSG_WHISPER','Ignored spell list: [Fireball]','Bot')
assert(PBM.State.strategyPending.Bot==nil)

-- A reused class menu must not receive the previous bot's state.
local updates=0
PBM.UpdateStrategyToggles=function() updates=updates+1 end
menu.botName='A'
PBM.QueryBotStrategies('A',menu,false)
local a=tokenFor('STATE')
menu.botName='B'
PBM.QueryBotStrategies('B',menu,false)
state('A',a)
assert(updates==0)
state('B',tokenFor('STATE'))
assert(updates==2)
-- A superseded query for the same bot must not resolve the new query.
PBM.QueryBotStrategies('B',menu,false)
local old=tokenFor('STATE')
PBM.QueryBotStrategies('B',menu,false)
local current=PBM.State.strategyPending.B
state('B',old)
assert(PBM.State.strategyPending.B==current and updates==2)
state('B',tokenFor('STATE'))
assert(updates==4)

-- Empty bridge stats fall back to the same sequential legacy chain.
menu.botName='Bot'; applied={}
PBM.QueryBotStrategies('Bot',menu,true)
state('Bot',tokenFor('STATE'))
receive('STATS_RESULT',tokenFor('STATS')..'~')
assert(chat[#chat].msg=='stats')
core.scripts.OnEvent(core,'CHAT_MSG_WHISPER','Bag, 4/20 Dur 100','Bot')
assert(tokenFor('DETAIL'))
receive('DETAIL_RESULT',tokenFor('DETAIL')..'~')
assert(chat[#chat].msg=='who')
core.scripts.OnEvent(core,'CHAT_MSG_WHISPER','Bot (80 lvl)','Bot')
assert(chat[#chat].msg=='ss ?')

local frameCount=#frames
for _=1,100 do
    local _,t=PBM.BridgeRequestStats('Bot',function() end)
    receive('STATS_RESULT',t..'~Bot~80~0~0~0~0~20~100~0~0')
end
assert(#frames==frameCount, 'completed reads must reuse the timer frame')
for _, frame in ipairs(frames) do
    if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame,6); assert(not frame.shown) end
end
local fired=0
PBM.TimerAfter(0.1,function() fired=fired+1; PBM.TimerAfter(0.1,function() fired=fired+1 end) end)
for _, frame in ipairs(frames) do if frame.scripts.OnUpdate and frame.shown then frame.scripts.OnUpdate(frame,0.1) end end
assert(fired==1)
for _, frame in ipairs(frames) do if frame.scripts.OnUpdate and frame.shown then frame.scripts.OnUpdate(frame,0.1) end end
assert(fired==2 and #frames==frameCount)
-- Bridge links must keep instance-specific enchants, gems and random properties.
local link = 'item:123:3789:40111:40112:40113:0:-42:12345:80'
local receivedGear, gearError
local _, linkToken = PBM.BridgeRequestGear('Bot', function(value, err) receivedGear, gearError = value, err end)
receive('GEAR_BEGIN','Bot~'..linkToken)
receive('GEAR_SUMMARY','Bot~'..linkToken..'~200~4000')
receive('GEAR_ITEM','Bot~'..linkToken..'~15~123~200~4')
receive('GEAR_LINK','Bot~'..linkToken..'~15~'..link)
receive('GEAR_END','Bot~'..linkToken)
assert(receivedGear.ilvlLink[15] == link and not gearError)
_, linkToken = PBM.BridgeRequestGear('Bot', function(value, err) receivedGear, gearError = value, err end)
receive('GEAR_SUMMARY','Bot~'..linkToken..'~200~4000')
receive('GEAR_ITEM','Bot~'..linkToken..'~15~123~200~4')
receive('GEAR_END','Bot~'..linkToken)
assert(not receivedGear and gearError == 'MISSING_GEAR_LINK')
PBM.Bridge.capabilities.GEAR_ITEM_LINK_V1 = nil
assert(not PBM.BridgeRequestGear('Bot', function() error('Old bridge must use native inspect') end))
print('PASS bridge: sender, slots, UTF-8, empty results, query lifecycle, stale menus and timer reuse')
