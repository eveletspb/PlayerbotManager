local frames, buttons = {}, {}
local function Widget(name)
    local widget = { shown = true, scroll = 0 }
    function widget:SetSize(_, height) self.height = height end
    function widget:SetHeight(height) self.height = height end
    function widget:SetScrollChild(child) self.child = child end
    function widget:SetVerticalScroll(offset) self.scroll = offset end
    function widget:GetVerticalScroll() return self.scroll end
    function widget:GetFrameLevel() return 1 end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:CreateFontString() return Widget() end
    function widget:SetText(text) self.text = text end
    function widget:SetScript(event, callback) self[event] = callback end
    if name then frames[name] = widget end
    return setmetatable(widget, { __index = function() return function() end end })
end
local frameCount = 0
function CreateFrame(kind, name)
    local widget = Widget(name)
    frameCount = frameCount + 1
    if kind == "Button" then buttons[#buttons + 1] = widget end
    return widget
end

local statics = {}
for index = 1, 20 do statics[index] = { name = "Static " .. index } end
StaticPopupDialogs = {}
local dialog, selected, destination, editData
function StaticPopup_Show(id, title, target, data) dialog, selected, destination, editData = id, title, target, data end
PBM = { State = {}, GetStatics = function() return statics end }
dofile("PBM/PBM_Tab_Statics.lua")
PBM.BuildStaticsPanel(Widget())
LichborneTrackerDB = { raidName = "Current", raidGroup = "B" }
statics[1].raidName = "Other raid"
local loaded
PBM.LoadStatic = function(index) loaded = index; return true end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
buttons[3].OnClick()
assert(dialog == "PBM_EDIT_STATIC_TAB" and destination == "Other raid (B)" and not loaded)
LichborneTrackerDB.raidGroup = "A"
StaticPopupDialogs[dialog].OnAccept(nil, editData)
assert(not loaded)
LichborneTrackerDB.raidGroup = "B"
StaticPopupDialogs[dialog].OnAccept(nil, editData)
assert(loaded == 1 and PBM.State.activeTab == "Raid")
local scroll = frames.PBMStaticsScrollFrame
assert(scroll.child.height == 20 * 42)
scroll:SetVerticalScroll(scroll.child.height - scroll.height)
local initialFrames = frameCount
for _ = 1, 50 do PBM.RefreshStaticsPanel() end
assert(frameCount == initialFrames and scroll.scroll > 0)
statics[20].name = "Renamed"
PBM.RefreshStaticsPanel()
buttons[#buttons].OnClick()
assert(dialog == "PBM_DELETE_STATIC_TAB" and selected == "Renamed" and PBM.State.pendingStaticIndex == 20)
statics = {}
PBM.RefreshStaticsPanel()
assert(scroll.scroll == 0 and scroll.child.height == scroll.height)
print("PASS Statics: scroll range, stable row count and last-row actions")
