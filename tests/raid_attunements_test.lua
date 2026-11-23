local scripts, sent = {}, {}
local members = { { "Owner", true }, { "Bot", true }, { "Offline", false } }
local leader = true
function CreateFrame()
    return {
        RegisterEvent = function() end,
        SetScript = function(_, event, callback) scripts[event] = callback end,
    }
end
function GetNumRaidMembers() return #members end
function GetRaidRosterInfo(index)
    local member = members[index]
    return member[1], nil, nil, nil, nil, nil, nil, member[2]
end
function IsRaidLeader() return leader end
function ChatFrame_AddMessageEventFilter() end
PBM = {
    State = { groupViewFrame = { IsVisible = function() return true end } },
    SendChatMessage = function(command, channel, _, _, current)
        assert(channel == "SAY")
        sent[#sent + 1] = { command = command, current = current }
    end,
}
dofile("PBM/PBM_RaidAttunements.lua")
local attune = PBM.RaidAttunements
local function reply(line)
    scripts.OnEvent(nil, "CHAT_MSG_SYSTEM", "PBM_ATTUNE_V1 " .. line)
end
local function dispatch(command)
    local entry = sent[#sent]
    assert(entry.command == ".ip attune raid " .. command)
    assert(entry.current())
end

PBM.RefreshRaidAttunementRoster()
dispatch("list")
reply("BEGIN list 3")
reply("ROW Owner onyxia40,naxx40 source")
reply("ROW Bot - unchanged")
reply("ROW Offline - offline")
assert(not attune.ready)
reply("END list ok")
assert(attune.ready and not attune.busy and not attune.message)
assert(PBM.RaidAttunementRowText("OWNER") == "Ony Naxx")
assert(PBM.RaidAttunementRowText("Bot") == "None")
assert(PBM.RaidAttunementRowText("Offline") == "Offline")
assert(PBM.RaidAttunementRowText("Unknown") == "—")

leader = false
assert(not PBM.RequestRaidAttunements("sync"))
leader = true
assert(PBM.RequestRaidAttunements("sync"))
assert(not PBM.RequestRaidAttunements("sync"))
dispatch("sync")
reply("BEGIN list 1")
reply("ROW Intruder onyxia40 source")
reply("END list ok")
assert(attune.busy and not attune.rows.intruder)
reply("BEGIN sync 3")
reply("ROW Owner onyxia40,naxx40 source")
reply("FAIL Bot naxx40 quest_in_progress")
reply("ROW Bot onyxia40 partial")
reply("ROW Offline - offline")
reply("END sync partial")
assert(attune.ready and not attune.busy and attune.message)
assert(attune.rows.bot.failures.naxx40 == "Quest already in progress")
assert(PBM.RaidAttunementRowText("Bot") == "Ony")

assert(not PBM.RequestRaidAttunements("grant", "incorrect"))
assert(PBM.RequestRaidAttunements("grant", "naxx40"))
dispatch("grant naxx40")
reply("BEGIN grant 3")
reply("ROW Owner onyxia40,naxx40 source")
reply("ROW Owner onyxia40,naxx40 source")
reply("ROW Bot onyxia40,naxx40 granted")
reply("END grant ok")
assert(not attune.ready and not attune.busy and not next(attune.rows))

PBM.RefreshRaidAttunementRoster()
dispatch("list")
reply("BEGIN list 1")
reply("ROW Owner onyxia40,naxx40 source")
reply("END list ok")
assert(PBM.RequestRaidAttunements("sync"))
local queued = sent[#sent]
members[2] = { "Replacement", true }
scripts.OnEvent(nil, "RAID_ROSTER_UPDATE")
assert(not queued.current())
dispatch("list")
scripts.OnUpdate(nil, 9)
assert(not attune.ready and not attune.busy and not scripts.OnUpdate)
assert(sent[#sent].command == ".ip attune raid list")
assert(not PBM.RequestRaidAttunements("grant", "naxx40"))

PBM.RefreshRaidAttunementRoster()
dispatch("list")
reply("BEGIN list 40")
for index = 1, 40 do reply("ROW Member" .. index .. " - unchanged") end
reply("END list ok")
assert(attune.ready and attune.rows.member40)

members = {}
scripts.OnEvent(nil, "RAID_ROSTER_UPDATE")
assert(not attune.ready and not next(attune.rows))
assert(not PBM.RequestRaidAttunements("list"))
print("PASS raid attunements: complete and malformed replies, partial grants, queue guards, timeout and 40 members")

-- Drive the Group view's real OnShow, menu and row callbacks with WoW frame stubs.
local frames = {}
local frameMethods = {}
local function makeFrame()
    local object = {
        callbacks = {},
        GetFrameLevel = function() return 0 end,
        CreateFontString = function() return makeFrame() end,
        CreateTexture = function() return makeFrame() end,
        SetScript = function(self, event, callback) self.callbacks[event] = callback end,
        SetText = function(self, value) self.text = value end,
        Enable = function(self) self.enabled = true end,
        Disable = function(self) self.enabled = false end,
    }
    frames[#frames + 1] = object
    return setmetatable(object, frameMethods)
end
frameMethods.__index = function() return function() end end
CreateFrame = makeFrame
LichborneTrackerDB = { rows = {} }
PBM.State.LBFilter = {}
PBM.CLASS_TABS = {}
PBM.GEAR_SLOTS, PBM.ALL_NCOLS, PBM.ALL_COL_W = 17, 3, 362
PBM.COL_NEEDS_W, PBM.SLOT_ABBR = 42, {}
PBM.MakeProfCell = function() return makeFrame() end
PBM.RefreshProfCell = function() end
PBM.HookRowHighlight = function() end
PBM.GetItemQualityColor = function() end
members = { { "Owner", true }, { "Bot", true }, { "Offline", false } }
local openedMenu
function EasyMenu(entries) openedMenu = entries end
dofile("PBM/PBM_GroupView.lua")
PBM.BuildGroupView(makeFrame(), 0)
PBM.State.groupViewFrame.callbacks.OnShow()
dispatch("list")
reply("BEGIN list 3")
reply("ROW Owner onyxia40 source")
reply("ROW Bot - unchanged")
reply("ROW Offline - offline")
reply("END list ok")
local byText = {}
for _, frame in ipairs(frames) do
    if type(rawget(frame, "text")) == "string" then byText[frame.text] = frame end
end
assert(byText["Grant..."].enabled and byText["Sync from me"].enabled)
assert(byText["Ony 1/2   Naxx 0/2   SSC 0/2   TK 0/2   Hyjal 0/2   BT 0/2   Offline 1"])
assert(PBM.State.groupViewRowFrames[2].attunements.text == "Offline")
byText["Grant..."].callbacks.OnClick(byText["Grant..."])
assert(#openedMenu == 6)
openedMenu[2].func()
dispatch("grant naxx40")
assert(not byText["Grant..."].enabled and not byText["Sync from me"].enabled)
print("PASS Group view: opening, row column, raid coverage and Grant menu")
