local frames, sent = {}, {}
local function widget()
    local f={frames={},buttons={},texts={},scripts={},shown=true,index=0,size=28,width=170,height=408}
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    function f:IsVisible() return self.shown end
    function f:SetScript(k,v) self.scripts[k]=v end
    function f:RegisterEvent(event) self.event=event end
    function f:SetAllPoints() end
    function f:SetMovable() end
    function f:SetFrameLevel() end
    function f.addFrame(name) local child=widget(); f.frames[name]=child; return child end
    function f.addButton(name,_,_,_,tip)
        local child=widget(); child.tip=tip; f.buttons[name]=child; return child
    end
    f.wowButton=f.addButton; f.movButton=f.addButton; f.boxButton=f.addButton
    f.catButton=f.addButton
    function f.addTexture() end
    function f.addText(key,text) f.texts[key]=widget(); f.texts[key].text=text end
    function f.setText(key,text) f.texts[key].text=text end
    function f.setButton(key,_,tip) f.buttons[key].tip=tip end
    function f:SetChecked(value) self.checked=value end
    function f:Enable() self.enabled=true end
    function f:Disable() self.enabled=false end
    function f.setAmount() end
    function f.setAlpha() return f end
    function f.setLevel() return f end
    function f.setTexture() return f end
    function f:GetFrameLevel() return 0 end
    function f.setEnable() f.state=true; return f end
    function f.setDisable() f.state=false; return f end
    function f.doShow() f:Show(); return f end
    function f.doHide() f:Hide(); return f end
    function f:RegisterForClicks() end
    for _, method in ipairs({'ClearAllPoints','SetPoint','SetSize','SetWidth','SetHeight','SetTexture','SetAlpha','SetNormalTexture','SetHighlightTexture','EnableMouse'}) do
        f[method]=function() end
    end

    frames[#frames+1]=f
    return f
end
function CreateFrame() return widget() end
function GetNumMacroIcons() return 0 end
function table.wipe(t) for k in pairs(t) do t[k]=nil end end
function UnitName() return 'Owner' end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function GetTime() return 100 end
function SendAddonMessage(_,payload) sent[#sent+1]={wire=payload} end
function SendChatMessage(msg,_,_,target) sent[#sent+1]={msg=msg,target=target} end
function GetItemIcon() return 'icon' end
function GetItemInfo() return 'Item','|cffffffff|Hitem:100:0|h[Item]|h|r',1 end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
UIParent=widget()
dofile('PBM/PBM_UI.lua')
dofile('PBM/PBM_Bridge.lua')
dofile('PBM/PBM_Engine.lua')
PBM.newFrame=function() return widget() end
PBM.SendChatMessage=SendChatMessage
PBM.AfterChatQueue=function(callback) callback() end
dofile('PBM/PBM_Item.lua')
dofile('PBM/PBM_Spell.lua')
dofile('PBM/PBM_Windows.lua')
local whisper, talentTimer
for _, f in ipairs(frames) do
    if f.event=='CHAT_MSG_WHISPER' then whisper=f end
    if f.scripts.OnUpdate then talentTimer=f end
end
local function receive(op,payload) PBM.HandleBridgeAddonMessage('MBOT',op..'~'..payload,'Owner') end
local function token() return sent[#sent].wire:match('([^~]+)$') end
PBM.Bridge.state='available'; PBM.Bridge.capabilities.INVENTORY_V1=true
local items=PBM.inventory.frames.Items
local line='|cffffffff|Hitem:100:0|h[Item]|h|r'
PBM.OpenInventoryWindow('A'); local a=token()
receive('INV_BEGIN','A~'..a); receive('INV_ITEM','A~'..a..'~'..line); receive('INV_END','A~'..a)
assert(PBM.inventory.name=='A' and PBM.inventory:IsVisible())
local oldButton=items.buttons.Item
PBM.inventory.action='destroy'
PBM.OpenInventoryWindow('B'); local b=token()
local count=#sent
oldButton.doLeft(oldButton)
assert(#sent==count and not PBM.inventory:IsVisible())
receive('INV_BEGIN','B~'..b); receive('INV_ITEM','B~'..b..'~'..line); receive('INV_END','B~'..b)
assert(PBM.inventory.name=='B' and not PBM.inventory.loading)
oldButton.doLeft(oldButton)
assert(#sent==count)
local currentButton=items.buttons.Item
currentButton.doLeft(currentButton)
assert(sent[#sent].target=='B' and sent[#sent].msg:find('destroy',1,true))
-- Refresh uses the same public request path; there is no MultiBar in PBM.
assert(PBM.frames.MultiBar==nil)
assert(PBM.RefreshInventory(0))
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f~=talentTimer and f.shown then f.scripts.OnUpdate(f,0.1) end end
assert(sent[#sent].wire:find('GET~INVENTORY~B~',1,true))
local refresh=token()
receive('INV_BEGIN','B~'..refresh); receive('INV_END','B~'..refresh)
-- A superseded request must not open or overwrite the new inventory.
PBM.OpenInventoryWindow('A'); a=token()
PBM.OpenInventoryWindow('B'); b=token()
receive('INV_BEGIN','A~'..a); receive('INV_ITEM','A~'..a..'~'..line); receive('INV_END','A~'..a)
assert(not PBM.inventory:IsVisible() and PBM.inventory.request.name=='B')
receive('INV_BEGIN','B~'..b); receive('INV_END','B~'..b)
-- Closing while waiting invalidates its late snapshot.
PBM.OpenInventoryWindow('A'); a=token()
PBM.inventory.buttons.X.doLeft()
receive('INV_BEGIN','A~'..a); receive('INV_END','A~'..a)
assert(not PBM.inventory:IsVisible() and PBM._waitFor.A==nil)
-- Legacy inventory still populates, completes, and binds item actions to its owner.
PBM.Bridge.state='unavailable'
PBM.OpenInventoryWindow('A')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Inventory','A')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER',line,'A')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','A')
assert(PBM.inventory:IsVisible() and not PBM.inventory.loading and PBM._waitFor.A==nil)
-- A delayed refresh of A must not replace a newly requested B inventory.
assert(PBM.RefreshInventory(0.1)); PBM.OpenInventoryWindow('B'); count=#sent
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f~=talentTimer and f.shown then f.scripts.OnUpdate(f,0.1) end end
assert(#sent==count)
-- Use the actual talent retry timer: missing data retries and stops within 15 seconds.
function PBM.NameToUnit() return 'party1' end
function UnitLevel() return 80 end
function CheckInteractDistance() return true end
function UnitClass() return 'Mage','MAGE' end
local inspected
function NotifyInspect(unit) inspected=unit end
-- The lock covers the delay before a target scan has an inspect target, too.
PBM.SetButtonsLocked(true)
PBM.OpenTalentWindow('A'); assert(inspected==nil)
PBM.SetButtonsLocked(false)
PBM.State.LichborneSpecTarget=1
PBM.OpenTalentWindow('A'); assert(inspected==nil)
PBM.State.LichborneSpecTarget=nil
LichborneUpdateTargetSpecBtn=widget()
LichborneUpdateGSBtn=widget()
PBM.OpenTalentWindow('A')
assert(inspected=='party1' and PBM.auto.talent)
assert(not LichborneUpdateTargetSpecBtn.enabled and not LichborneUpdateGSBtn.enabled)
-- Stop/other UI unlocks cannot enable scans while the talent read is pending.
PBM.SetButtonsLocked(false)
assert(PBM.State.buttonsLocked and not LichborneUpdateTargetSpecBtn.enabled)
PBM.talent.class='Mage'; PBM.data.talent={talents={Mage={{'test'},{}, {}}},arrows={Mage={{},{},{}}}}
function GetActiveTalentGroup() return 1 end
local reads=0
function GetTalentInfo() reads=reads+1; return nil end
function GetTalentLink() return nil end
PBM.auto.talent=true; PBM.timer.talent.elapsed=0; PBM.timer.talent.waited=0
for _=1,15 do talentTimer.scripts.OnUpdate(talentTimer,1) end
assert(reads==4 and not PBM.auto.talent)
assert(not PBM.State.buttonsLocked and LichborneUpdateTargetSpecBtn.enabled and LichborneUpdateGSBtn.enabled)
-- The same retry path succeeds when the inspect data becomes available.
function GetTalentInfo() return 'Talent','icon',1,1,0 end
function GetTalentLink() return '|cffffffff|Htalent:123:0|h[Talent]|h|r' end
function GetUnspentTalentPoints() return 1 end
PBM.data.talent.talents.Mage={{'0, 0, 1, 1, 42'},{},{}}
PBM.talent.name='A'
PBM.OpenTalentWindow('A')
for _=1,3 do talentTimer.scripts.OnUpdate(talentTimer,1) end
assert(PBM.talent:IsVisible() and not PBM.auto.talent and PBM.talent.frames.Tab1.buttons[1])
assert(not PBM.State.buttonsLocked and LichborneUpdateTargetSpecBtn.enabled)
local function tick(dt)
    for _,frame in ipairs(frames) do
        if frame.scripts.OnUpdate and frame~=talentTimer and frame.shown then frame.scripts.OnUpdate(frame,dt) end
    end
end
-- A silent bridge plus silent legacy read must release the request and permit a retry.
PBM.Bridge.state='available'
PBM.OpenInventoryWindow('Offline')
tick(6)
assert(PBM._waitFor.Offline=='INVENTORY')
tick(15)
assert(PBM._waitFor.Offline==nil and PBM.inventory.request==nil and not PBM.inventory.loading)
local before=#sent
PBM.OpenInventoryWindow('Offline')
assert(#sent==before+1)
local retry=token()
receive('INV_BEGIN','Offline~'..retry); receive('INV_END','Offline~'..retry)
-- Expiry of a superseded legacy request cannot cancel the new inventory.
PBM.Bridge.state='unavailable'
PBM.OpenInventoryWindow('LegacyA'); tick(10)
PBM.OpenInventoryWindow('LegacyB'); tick(5)
assert(PBM._waitFor.LegacyB=='INVENTORY' and PBM.inventory.request.name=='LegacyB')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Inventory','LegacyB')
local index=items.index
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Strategies: fire, dps assist','LegacyB')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Random bot text','LegacyB')
assert(items.index==index)
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER',line,'LegacyB')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','LegacyB')
assert(items.index==index+1 and not PBM.inventory.loading)
-- Spellbook buttons remain disabled until the requested owner's complete snapshot arrives.
function GetSpellInfo() return 'Fireball','Rank 1','icon' end
function GetSpellLink() return '|cffffffff|Hspell:123|h[Fireball]|h|r' end
PBM.OpenSpellbookWindow('SpellA')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Spells','SpellA')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER',GetSpellLink(),'SpellA')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','SpellA')
local spell=PBM.spellbook.frames.Overlay.buttons.S01
spell.doLeft(spell)
assert(sent[#sent].target=='SpellA' and sent[#sent].msg=='cast 123')
PBM.OpenSpellbookWindow('SpellB'); before=#sent
spell.doLeft(spell)
assert(#sent==before and not PBM.spellbook:IsVisible())
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Spells','SpellA')
assert(PBM.spellbook.name=='SpellA')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Spells','SpellB')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Strategies: fire','SpellB')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER',GetSpellLink(),'SpellB')
spell.doLeft(spell); assert(#sent==before+1) -- only the stats request was sent
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','SpellB')
spell.doLeft(spell)
assert(sent[#sent].target=='SpellB')
local macroOwner
PBM.SpellToMacro=function(owner) macroOwner=owner end
spell.doRight(spell); assert(macroOwner=='SpellB')
PBM.OpenSpellbookWindow('SilentSpellbook'); tick(15)
assert(PBM._waitFor.SilentSpellbook==nil and not PBM.spellbook.loading)
PBM.OpenSpellbookWindow('EmptySpellbook')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Spells','EmptySpellbook')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','EmptySpellbook')
before=#sent; spell.doLeft(spell)
assert(#sent==before and not spell.shown)
-- Closing a completed snapshot must not cancel the other window's active read.
PBM.OpenInventoryWindow('Shared')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Inventory','Shared')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','Shared')
PBM.OpenSpellbookWindow('Shared')
PBM.inventory.buttons.X.doLeft()
assert(PBM._waitFor.Shared=='SPELLBOOK' and PBM.spellbook.loading)
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Spells','Shared')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER',GetSpellLink(),'Shared')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','Shared')
assert(PBM.spellbook:IsVisible() and not PBM.spellbook.loading)
PBM.OpenInventoryWindow('Shared')
PBM.spellbook.frames.Overlay.buttons.X.doLeft()
assert(PBM._waitFor.Shared=='INVENTORY' and PBM.inventory.loading)
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Inventory','Shared')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER',line,'Shared')
whisper.scripts.OnEvent(whisper,'CHAT_MSG_WHISPER','Bag, 1/20 Dur 100','Shared')
assert(PBM.inventory:IsVisible() and not PBM.inventory.loading)
-- Old timeout callbacks for those completed windows must leave a new read alone.
PBM.OpenSpellbookWindow('Shared'); tick(15)
assert(PBM._waitFor.Shared==nil and not PBM.spellbook.loading)
PBM.OpenSpellbookWindow('Shared')
PBM.spellbook.frames.Overlay.buttons.X.doLeft()
assert(PBM._waitFor.Shared==nil and not PBM.spellbook.loading)
-- The PBM popup must not replace or use MultiBot's callback or data schema.
StaticPopupDialogs={MULTIBOT_CONFIRM_DESTROY={OnAccept=function() error('MultiBot callback used by PBM') end}}
OKAY='OK'; CANCEL='Cancel'
local popupId,popupData
function StaticPopup_Show(id,_,_,data) popupId,popupData=id,data end
function GetItemInfo() return 'Epic','|cffa335ee|Hitem:100:0|h[Epic]|h|r',4 end
PBM.inventory.name='LegacyB'; PBM.inventory.loading=false; PBM.inventory.action='destroy'
PBM.addItem(items,'|cffa335ee|Hitem:100:0|h[Epic]|h|r')
items.buttons.Epic.doLeft(items.buttons.Epic)
assert(popupId=='PBM_CONFIRM_DESTROY' and StaticPopupDialogs.MULTIBOT_CONFIRM_DESTROY)
StaticPopupDialogs[popupId].OnAccept(nil,popupData)
assert(sent[#sent].target=='LegacyB' and sent[#sent].msg:find('destroy',1,true))
print('PASS windows: inventory/spellbook ownership, timeout recovery, parsers, popup isolation and talent retries')
