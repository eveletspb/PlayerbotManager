local file = assert(io.open("PBM/PBM_Tab_LevelSync.lua"))
local source = file:read("*a")
file:close()
local first = assert(source:find("    local function lsSendCmd", 1, true))
local last = assert(source:find("    -- ── Multi-line", first, true))

local sent
PBM = { SendChatMessage = function(command, channel) sent = {command, channel} end }
function InCombatLockdown() return false end
ChatFrame1EditBox = setmetatable({}, { __index = function() error("player chat was accessed") end })
assert(loadstring(source:sub(first, last - 1)))()
PBM.LevelSyncAutoRefresh()
assert(sent[1] == ".levelsync status" and sent[2] == "SAY")

local frames, filter = {}, nil
function CreateFrame()
    local frame = {}
    function frame:SetScript(event, fn) self[event] = fn end
    function frame:RegisterEvent() end
    function frame:Show() end
    function frame:Hide() end
    frames[#frames + 1] = frame
    return frame
end
function ChatFrame_AddMessageEventFilter(_, fn) filter = fn end
local stateStart = assert(source:find("    local lsData =", 1, true))
local stateEnd = assert(source:find("    ChatFrame_AddMessageEventFilter", stateStart, true))
stateEnd = assert(source:find("\n", stateEnd, true))
local data = assert(loadstring(source:sub(stateStart, stateEnd) .. "\nreturn lsData"))()
local function system(line) frames[2].OnEvent(nil, "CHAT_MSG_SYSTEM", line) end
system("|cff00ff00[LevelSync]|r Sync Group #7")
assert(filter(nil, nil, "  Accounts: 1/6"))
system("  Accounts: 1/6")
system("  Account 8: Characters: 1")
system("    Magebot (lvl 80) (Mage) IP Tier: 1 - Classic")
frames[1].OnUpdate(frames[1], 0.2)
assert(not filter(nil, nil, "You are now Away"))
system("You are now Away")
frames[1].OnUpdate(frames[1], 0.15)
assert(data.groupId == 7 and data.accountsCur == 1 and data.members[1].name == "Magebot")
print("PASS LevelSync: queue preserves chat and status ignores unrelated system lines")
