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
print("PASS LevelSync: status uses PBM queue and leaves player chat untouched")
