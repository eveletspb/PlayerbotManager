local frames, sent, notes, errors={}, {}, {}, {}
function CreateFrame()
    local f={scripts={},events={},shown=true}
    function f:SetScript(key,value) self.scripts[key]=value end
    function f:RegisterEvent(event) self.events[event]=true end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    frames[#frames+1]=f; return f
end
function GetTime() return 100 end
function UnitName() return 'Owner' end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function SendAddonMessage() end
function SendChatMessage(msg,_,_,target) sent[#sent+1]={msg=msg,target=target} end
function ChatFrame_AddMessageEventFilter() end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,msg) errors[#errors+1]=msg end}
dofile('PBM/PBM_Bridge.lua')
dofile('PBM/PBM_Throttle.lua')
dofile('PBM/PBM_Commands.lua')
dofile('PBM/PBM_Core.lua')
PBM.ApplyBotNotes=function(name,co,nc) notes[#notes+1]={name=name,co=co,nc=nc} end
PBM.UpdateStrategyToggles=function() end
local core
for _,f in ipairs(frames) do if f.events.CHAT_MSG_WHISPER then core=f end end
local function tick(dt)
    local count=#frames
    for i=1,count do
        local f=frames[i]
        if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f,dt) end
    end
end
local function reply(message,name) core.scripts.OnEvent(core,'CHAT_MSG_WHISPER',message,name or 'Bot') end
local function command(expected)
    tick(0.25)
    assert(sent[#sent].msg==expected, expected..' vs '..sent[#sent].msg)
end
-- Background queries complete without a menu.
PBM.QueryBotStrategies('Bot',nil,false)
command('co ?'); reply('Strategies: fire, aoe')
command('nc ?'); reply('Strategies: food, loot')
assert(#notes==1 and notes[1].co.fire and notes[1].nc.food and not PBM.State.strategyPending.Bot)
-- A closed card does not interrupt an extended legacy query either.
PBM.QueryBotStrategies('Bot',nil,true)
command('co ?'); reply('Strategies: fire')
command('nc ?'); reply('Strategies: food')
command('stats'); reply('Bag, 4/20 Dur 100')
command('who'); reply('Bot (80 lvl)')
command('ss ?'); reply('Ignored spell list: [Fireball]')
assert(PBM.State.strategyPending.Bot==nil and #notes==2)
-- Rapid CO/NC mutations are sent one at a time and followed by one current snapshot.
local menu={botName='Bot',IsShown=function() return true end}
PBM.State.lastQueriedMenu.Bot=menu
local before=#sent
PBM.SendToBot('co +aoe,?','Bot')
PBM.SendToBot('nc +food,?','Bot')
command('co +aoe,?')
assert(#sent==before+1)
reply('Strategies: fire, aoe')
command('nc +food,?'); reply('Strategies: food')
-- The first refresh is superseded by the later mutation's refresh.
command('co ?'); reply('Strategies: fire, aoe')
command('co ?'); reply('Strategies: fire, aoe')
command('nc ?'); reply('Strategies: food')
assert(#notes==3 and notes[3].co.aoe and notes[3].nc.food and not notes[3].nc.fire)
-- A replaced request cannot advance the replacement's state machine.
PBM.QueryBotStrategies('Bot',menu,false)
PBM.QueryBotStrategies('Bot',menu,false)
command('co ?'); reply('Strategies: stale')
command('co ?'); reply('Strategies: fire')
command('nc ?'); reply('Strategies: food')
assert(#notes==4 and notes[4].co.fire and not notes[4].co.stale)
-- Timeout drops unsent commands for this bot; a late reply cannot run the next mutation.
PBM.QueryBotStrategies('Bot',nil,false)
PBM.SendToBot('nc +food,?','Bot')
command('co ?'); before=#sent
local errorCount=#errors
tick(6); reply('Strategies: late'); tick(1)
assert(#sent==before and #errors==errorCount+1 and PBM.State.strategyPending.Bot==nil)
-- Other bots and a fresh retry still work after that timeout.
PBM.QueryBotStrategies('Other',nil,false)
command('co ?'); reply('Strategies: tank','Other')
command('nc ?'); reply('Strategies: food','Other')
assert(notes[#notes].name=='Other' and notes[#notes].co.tank)
PBM.QueryBotStrategies('Bot',nil,false)
command('co ?'); reply('Strategies: fire')
command('nc ?'); reply('Strategies: food')
assert(notes[#notes].name=='Bot' and notes[#notes].co.fire)
-- A bridge state timeout falls back to this same legacy chain.
PBM.Bridge.state='available'; PBM.Bridge.capabilities.STATE_FRAMING_V1=true
PBM.QueryBotStrategies('Bot',nil,false)
tick(6)
command('co ?'); reply('Strategies: fire')
command('nc ?'); reply('Strategies: food')
assert(notes[#notes].co.fire and PBM.State.strategyPending.Bot==nil)
print('PASS legacy: background/extended queries, rapid toggles, superseded requests and timeout recovery')
