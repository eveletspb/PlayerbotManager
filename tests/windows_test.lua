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
    function f.addText(key,text) f.texts[key]=text end
    function f.setText(key,text) f.texts[key]=text end
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
dofile('PBM/PBM_Bridge.lua')
dofile('PBM/PBM_Engine.lua')
PBM.newFrame=function() return widget() end
PBM.SendChatMessage=SendChatMessage
PBM.AfterChatQueue=function(callback) callback() end
dofile('PBM/PBM_Item.lua')
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
PBM.talent.class='Mage'; PBM.data.talent={talents={Mage={{'test'},{}, {}}},arrows={Mage={{},{},{}}}}
function GetActiveTalentGroup() return 1 end
local reads=0
function GetTalentInfo() reads=reads+1; return nil end
function GetTalentLink() return nil end
PBM.auto.talent=true; PBM.timer.talent.elapsed=0; PBM.timer.talent.waited=0
for _=1,15 do talentTimer.scripts.OnUpdate(talentTimer,1) end
assert(reads==4 and not PBM.auto.talent)
-- The same retry path succeeds when the inspect data becomes available.
function GetTalentInfo() return 'Talent','icon',1,1,0 end
function GetTalentLink() return '|cffffffff|Htalent:123:0|h[Talent]|h|r' end
function GetUnspentTalentPoints() return 1 end
function table.wipe(t) for k in pairs(t) do t[k]=nil end end
PBM.data.talent.talents.Mage={{'0, 0, 1, 1, 42'},{},{}}
PBM.talent.name='A'
PBM.auto.talent=true; PBM.timer.talent.elapsed=0; PBM.timer.talent.waited=0
for _=1,3 do talentTimer.scripts.OnUpdate(talentTimer,1) end
assert(PBM.talent:IsVisible() and not PBM.auto.talent and PBM.talent.frames.Tab1.buttons[1])
print('PASS windows: inventory ownership, late replies, refresh, legacy parsing and bounded talent retries')
